import { readCredential } from "./credentials.ts";
import { db } from "./db.ts";
import { GoogleSession, ReauthRequiredError } from "./google_auth.ts";
import { googleEventBody } from "./google_export.ts";
import { importGoogleEvent, type GoogleEvent } from "./google_import.ts";
import { withConnectionInboundLock } from "./inbound_work.ts";
import { patchMatchesRow } from "./mapped.ts";
import {
  importNotionPage,
  type NotionBlock,
  type NotionPage,
} from "./notion_import.ts";
import {
  notionBody,
  notionHeaders,
  notionProperties,
  omitLegacyRemoteTitle,
} from "./notion_export.ts";
import { listBlockChildren } from "./notion_worker.ts";

export type ResolveChoice = "keep_local" | "use_remote";

export type LiveKind =
  | "equal"
  | "drift"
  | "unsupported_content"
  | "unsupported_timed_event"
  | "unsupported_recurrence"
  | "remote_deleted"
  | "fetch_failed";

export type ResolveDecision =
  | { action: "already_resolved"; status: string }
  | { action: "error"; code: string }
  | { action: "push_then_keep_local" }
  | { action: "finish_keep_local"; acceptRemoteGone: boolean }
  | { action: "apply_then_use_remote" }
  | { action: "finish_use_remote_equal" }
  | { action: "finish_use_remote_gone" };

export function decideConflictResolution(args: {
  loadResult: string;
  choice: ResolveChoice;
  liveKind: LiveKind;
  alreadyStatus?: string;
}): ResolveDecision {
  if (args.loadResult === "already_resolved") {
    return { action: "already_resolved", status: args.alreadyStatus ?? "resolved" };
  }
  if (args.loadResult === "stale") {
    return { action: "error", code: "STALE_CONFLICT" };
  }
  if (args.loadResult === "not_found") {
    return { action: "error", code: "NOT_FOUND" };
  }
  if (args.loadResult === "inbound_disabled" || args.loadResult === "not_connected") {
    return { action: "error", code: "INBOUND_DISABLED" };
  }
  if (args.loadResult !== "ready") {
    return { action: "error", code: "VALIDATION" };
  }
  if (args.liveKind === "fetch_failed") {
    return { action: "error", code: "PROVIDER_UNAVAILABLE" };
  }
  if (args.choice === "keep_local") {
    if (args.liveKind === "remote_deleted") {
      return { action: "finish_keep_local", acceptRemoteGone: true };
    }
    if (args.liveKind === "equal") {
      return { action: "finish_keep_local", acceptRemoteGone: false };
    }
    return { action: "push_then_keep_local" };
  }
  if (
    args.liveKind === "unsupported_content" ||
    args.liveKind === "unsupported_timed_event" ||
    args.liveKind === "unsupported_recurrence"
  ) {
    return { action: "error", code: "UNSUPPORTED_REMOTE" };
  }
  if (args.liveKind === "remote_deleted") {
    return { action: "finish_use_remote_gone" };
  }
  if (args.liveKind === "equal") {
    return { action: "finish_use_remote_equal" };
  }
  return { action: "apply_then_use_remote" };
}

export function safeConflictPayload(row: Record<string, unknown>): Record<string, unknown> {
  return {
    id: row.id,
    connection_id: row.connection_id,
    provider: row.provider,
    entity_type: row.entity_type,
    entity_id: row.entity_id,
    status: row.status,
    reason: row.reason,
    local_revision: row.local_revision,
    last_synced_revision: row.last_synced_revision,
    created_at: row.created_at,
    entity_label: row.entity_label ?? null,
    field_categories: row.field_categories ?? [],
    can_keep_local_push: row.can_keep_local_push === true,
    can_use_remote: row.can_use_remote !== false,
    blocked_reason: row.blocked_reason ?? null,
  };
}

type SqlJson = Record<string, unknown>;

function jsonArg(value: Record<string, unknown>) {
  return db().json(JSON.parse(JSON.stringify(value)));
}

function sqlResult(rows: unknown): SqlJson {
  const list = rows as Array<{ result?: unknown }>;
  const value = list[0]?.result;
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as SqlJson;
  }
  return { result: value };
}

export async function listOpenConflicts(args: {
  userId: string;
  connectionId?: string | null;
}): Promise<Record<string, unknown>[]> {
  const rows = await db()`
    select integrations.list_open_conflict_summaries(
      ${args.userId}::uuid,
      ${args.connectionId ?? null}::uuid
    ) as result
  `;
  const result = rows[0]?.result;
  if (!Array.isArray(result)) {
    return [];
  }
  return result.map((item) => safeConflictPayload(item as Record<string, unknown>));
}

type LiveRemote = {
  kind: LiveKind;
  patch: Record<string, unknown>;
  remoteSnapshot: Record<string, unknown>;
  etag: string | null;
  updatedAt: string | null;
};

async function fetchLiveNotion(args: {
  token: string;
  entityType: string;
  externalId: string;
  currentRow: Record<string, unknown>;
  fetchImpl: typeof fetch;
}): Promise<LiveRemote> {
  const pageResponse = await args.fetchImpl(
    `https://api.notion.com/v1/pages/${args.externalId}`,
    { headers: notionHeaders(args.token) },
  );
  if (pageResponse.status === 404) {
    return {
      kind: "remote_deleted",
      patch: {},
      remoteSnapshot: { page_id: args.externalId, missing: true },
      etag: null,
      updatedAt: null,
    };
  }
  if (!pageResponse.ok) {
    return {
      kind: "fetch_failed",
      patch: {},
      remoteSnapshot: {},
      etag: null,
      updatedAt: null,
    };
  }
  const page = await pageResponse.json() as NotionPage;
  if (page.archived === true || page.in_trash === true) {
    return {
      kind: "remote_deleted",
      patch: {},
      remoteSnapshot: { page_id: args.externalId, archived: true },
      etag: null,
      updatedAt: page.last_edited_time ?? null,
    };
  }
  const blocks: NotionBlock[] = args.entityType === "inbox_items"
    ? []
    : await listBlockChildren(args.token, args.externalId, args.fetchImpl);
  const imported = importNotionPage({
    entityType: args.entityType as "inbox_items" | "memos" | "diary_entries",
    page,
    blocks,
    currentContent: String(args.currentRow.content ?? ""),
  });
  if (imported.kind === "remote_deleted") {
    return {
      kind: "remote_deleted",
      patch: {},
      remoteSnapshot: { page_id: args.externalId, missing: true },
      etag: null,
      updatedAt: imported.lastEditedTime ?? null,
    };
  }
  if (imported.kind === "unsupported_content") {
    return {
      kind: "unsupported_content",
      patch: {},
      remoteSnapshot: imported.remoteSnapshot ?? {},
      etag: null,
      updatedAt: imported.lastEditedTime ?? null,
    };
  }
  const patch = omitLegacyRemoteTitle({
    entityType: args.entityType,
    localTitle: String(args.currentRow.title ?? ""),
    localContent: String(args.currentRow.content ?? ""),
    patch: imported.patch,
  });
  const equal = patchMatchesRow(args.currentRow, patch);
  return {
    kind: equal ? "equal" : "drift",
    patch,
    remoteSnapshot: imported.remoteSnapshot ?? { patch },
    etag: null,
    updatedAt: imported.lastEditedTime ?? null,
  };
}

async function fetchLiveGoogle(args: {
  session: GoogleSession;
  calendarId: string;
  externalId: string;
  currentRow: Record<string, unknown>;
}): Promise<LiveRemote> {
  const url =
    `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(args.calendarId)}/events/${encodeURIComponent(args.externalId)}`;
  const response = await args.session.fetch(url);
  if (response.status === 404) {
    return {
      kind: "remote_deleted",
      patch: {},
      remoteSnapshot: { missing: true },
      etag: null,
      updatedAt: null,
    };
  }
  if (!response.ok) {
    return {
      kind: "fetch_failed",
      patch: {},
      remoteSnapshot: {},
      etag: null,
      updatedAt: null,
    };
  }
  const event = await response.json() as GoogleEvent;
  const imported = importGoogleEvent(event);
  if (imported.kind === "ignored") {
    return {
      kind: "fetch_failed",
      patch: {},
      remoteSnapshot: {},
      etag: null,
      updatedAt: null,
    };
  }
  if (imported.kind === "remote_deleted") {
    return {
      kind: "remote_deleted",
      patch: {},
      remoteSnapshot: imported.remoteSnapshot,
      etag: imported.etag,
      updatedAt: imported.updated,
    };
  }
  if (imported.kind === "unsupported_timed_event" || imported.kind === "unsupported_recurrence") {
    return {
      kind: imported.kind,
      patch: {},
      remoteSnapshot: imported.remoteSnapshot,
      etag: imported.etag,
      updatedAt: imported.updated,
    };
  }
  if (imported.kind !== "update") {
    return {
      kind: "fetch_failed",
      patch: {},
      remoteSnapshot: {},
      etag: null,
      updatedAt: null,
    };
  }
  const equal = patchMatchesRow(args.currentRow, imported.patch);
  return {
    kind: equal ? "equal" : "drift",
    patch: imported.patch,
    remoteSnapshot: imported.remoteSnapshot,
    etag: imported.etag,
    updatedAt: imported.updated,
  };
}

async function pushExistingNotion(args: {
  token: string;
  entityType: string;
  externalId: string;
  row: Record<string, unknown> & { id: string };
  fetchImpl: typeof fetch;
}): Promise<{ etag: string | null; updatedAt: string | null }> {
  const properties = notionProperties(args.entityType, args.row);
  const patched = await args.fetchImpl(`https://api.notion.com/v1/pages/${args.externalId}`, {
    method: "PATCH",
    headers: notionHeaders(args.token),
    body: JSON.stringify({ properties }),
  });
  if (patched.status === 404) {
    throw new Error("REMOTE_GONE");
  }
  if (!patched.ok) {
    throw new Error(`notion_patch_${patched.status}`);
  }
  if (args.entityType !== "inbox_items") {
    await (async () => {
      const listed = await args.fetchImpl(
        `https://api.notion.com/v1/blocks/${args.externalId}/children?page_size=100`,
        { headers: notionHeaders(args.token) },
      );
      if (listed.ok) {
        const payload = await listed.json() as { results?: Array<{ id?: string }> };
        for (const block of payload.results ?? []) {
          if (typeof block.id !== "string") {
            continue;
          }
          await args.fetchImpl(`https://api.notion.com/v1/blocks/${block.id}`, {
            method: "DELETE",
            headers: notionHeaders(args.token),
          });
        }
      }
      const children = notionBody(args.entityType, args.row);
      if (children.length === 0) {
        return;
      }
      const appended = await args.fetchImpl(
        `https://api.notion.com/v1/blocks/${args.externalId}/children`,
        {
          method: "PATCH",
          headers: notionHeaders(args.token),
          body: JSON.stringify({ children }),
        },
      );
      if (!appended.ok) {
        throw new Error(`notion_body_${appended.status}`);
      }
    })();
  }
  const payload = await patched.json() as { last_edited_time?: string };
  return { etag: null, updatedAt: payload.last_edited_time ?? null };
}

async function pushExistingGoogle(args: {
  session: GoogleSession;
  calendarId: string;
  externalId: string;
  row: Record<string, unknown> & { id: string };
}): Promise<{ etag: string | null; updatedAt: string | null }> {
  const url =
    `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(args.calendarId)}/events/${encodeURIComponent(args.externalId)}`;
  const body = googleEventBody(args.row, args.externalId);
  const patched = await args.session.fetch(url, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (patched.status === 404) {
    throw new Error("REMOTE_GONE");
  }
  if (!patched.ok) {
    throw new Error(`google_patch_${patched.status}`);
  }
  const payload = await patched.json() as { etag?: string; updated?: string };
  return { etag: payload.etag ?? null, updatedAt: payload.updated ?? null };
}

export async function resolveExternalConflict(args: {
  userId: string;
  conflictId: string;
  choice: ResolveChoice;
  expectedLocalRevision: number;
  fetchImpl?: typeof fetch;
}): Promise<{ ok: boolean; result: string; error?: { code: string }; status?: number }> {
  const fetchImpl = args.fetchImpl ?? fetch;
  const preview = sqlResult(await db()`
    select integrations.load_conflict_for_resolve(
      ${args.userId}::uuid,
      ${args.conflictId}::uuid,
      ${args.expectedLocalRevision}::bigint
    ) as result
  `);
  const loadResult = String(preview.result ?? "not_found");
  if (loadResult !== "ready" && loadResult !== "already_resolved") {
    const decided = decideConflictResolution({
      loadResult,
      choice: args.choice,
      liveKind: "equal",
    });
    if (decided.action === "error") {
      return { ok: false, result: "error", error: { code: decided.code }, status: 409 };
    }
  }
  if (loadResult === "already_resolved") {
    return { ok: true, result: "already_resolved" };
  }
  const connectionId = String((preview.conflict as SqlJson | undefined)?.connection_id ?? "");
  if (!connectionId) {
    return { ok: false, result: "error", error: { code: "NOT_FOUND" }, status: 404 };
  }

  return await withConnectionInboundLock(connectionId, async () => {
    const loaded = sqlResult(await db()`
      select integrations.load_conflict_for_resolve(
        ${args.userId}::uuid,
        ${args.conflictId}::uuid,
        ${args.expectedLocalRevision}::bigint
      ) as result
    `);
    const lockedResult = String(loaded.result ?? "not_found");
    if (lockedResult === "already_resolved") {
      return { ok: true, result: "already_resolved" };
    }
    if (lockedResult !== "ready") {
      const decided = decideConflictResolution({
        loadResult: lockedResult,
        choice: args.choice,
        liveKind: "equal",
      });
      if (decided.action === "error") {
        const status = decided.code === "STALE_CONFLICT" ? 409 : 400;
        return { ok: false, result: "error", error: { code: decided.code }, status };
      }
    }
    const conflict = loaded.conflict as SqlJson;
    const currentRow = loaded.current_row as Record<string, unknown> & { id: string };
    const container = (loaded.container ?? {}) as Record<string, unknown>;
    const provider = String(conflict.provider);
    const entityType = String(conflict.entity_type);
    const externalId = String(conflict.external_id);

    let live: LiveRemote;
    const credential = await readCredential(connectionId);
    if (!credential) {
      throw new ReauthRequiredError();
    }
    if (provider === "notion") {
      live = await fetchLiveNotion({
        token: credential.bundle.access_token,
        entityType,
        externalId,
        currentRow,
        fetchImpl,
      });
    } else {
      const session = new GoogleSession(
        connectionId,
        credential.bundle,
        credential.accessExpiresAt,
      );
      const calendarId = String(container.calendar_id ?? "primary");
      live = await fetchLiveGoogle({
        session,
        calendarId,
        externalId,
        currentRow,
      });
    }

    const decision = decideConflictResolution({
      loadResult: "ready",
      choice: args.choice,
      liveKind: live.kind,
    });
    if (decision.action === "error") {
      return {
        ok: false,
        result: "error",
        error: { code: decision.code },
        status: decision.code === "UNSUPPORTED_REMOTE" ? 409 : 400,
      };
    }

    let etag = live.etag;
    let updatedAt = live.updatedAt;
    if (decision.action === "push_then_keep_local") {
      try {
        if (provider === "notion") {
          const written = await pushExistingNotion({
            token: credential.bundle.access_token,
            entityType,
            externalId,
            row: currentRow,
            fetchImpl,
          });
          etag = written.etag;
          updatedAt = written.updatedAt;
        } else {
          const session = new GoogleSession(
            connectionId,
            credential.bundle,
            credential.accessExpiresAt,
          );
          const written = await pushExistingGoogle({
            session,
            calendarId: String(container.calendar_id ?? "primary"),
            externalId,
            row: currentRow,
          });
          etag = written.etag;
          updatedAt = written.updatedAt;
        }
      } catch (error) {
        if (error instanceof Error && error.message === "REMOTE_GONE") {
          const gone = sqlResult(await db()`
            select integrations.finish_conflict_keep_local(
              ${args.userId}::uuid,
              ${args.conflictId}::uuid,
              ${args.expectedLocalRevision}::bigint,
              ${null},
              ${null}::timestamptz,
              ${true}
            ) as result
          `);
          return { ok: gone.result === "resolved_local", result: String(gone.result) };
        }
        throw error;
      }
      const finished = sqlResult(await db()`
        select integrations.finish_conflict_keep_local(
          ${args.userId}::uuid,
          ${args.conflictId}::uuid,
          ${args.expectedLocalRevision}::bigint,
          ${etag},
          ${updatedAt}::timestamptz,
          ${false}
        ) as result
      `);
      return { ok: finished.result === "resolved_local", result: String(finished.result) };
    }

    if (decision.action === "finish_keep_local") {
      const finished = sqlResult(await db()`
        select integrations.finish_conflict_keep_local(
          ${args.userId}::uuid,
          ${args.conflictId}::uuid,
          ${args.expectedLocalRevision}::bigint,
          ${etag},
          ${updatedAt}::timestamptz,
          ${decision.acceptRemoteGone}
        ) as result
      `);
      return { ok: finished.result === "resolved_local", result: String(finished.result) };
    }

    if (decision.action === "finish_use_remote_gone") {
      const finished = sqlResult(await db()`
        select integrations.finish_conflict_use_remote(
          ${args.userId}::uuid,
          ${args.conflictId}::uuid,
          ${args.expectedLocalRevision}::bigint,
          ${"remote_deleted"},
          ${jsonArg({})}::jsonb,
          ${jsonArg(live.remoteSnapshot)}::jsonb,
          ${etag},
          ${updatedAt}::timestamptz,
          ${false}
        ) as result
      `);
      return { ok: finished.result === "resolved_remote", result: String(finished.result) };
    }

    const mappedEqual = decision.action === "finish_use_remote_equal";
    const finished = sqlResult(await db()`
      select integrations.finish_conflict_use_remote(
        ${args.userId}::uuid,
        ${args.conflictId}::uuid,
        ${args.expectedLocalRevision}::bigint,
        ${"update"},
        ${jsonArg(live.patch)}::jsonb,
        ${jsonArg(live.remoteSnapshot)}::jsonb,
        ${etag},
        ${updatedAt}::timestamptz,
        ${mappedEqual}
      ) as result
    `);
    if (finished.result === "inbox_relationship") {
      return { ok: false, result: "error", error: { code: "INBOX_RELATIONSHIP" }, status: 409 };
    }
    return { ok: finished.result === "resolved_remote", result: String(finished.result) };
  });
}
