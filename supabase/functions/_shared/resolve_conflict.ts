import { readCredential } from "./credentials.ts";
import { db } from "./db.ts";
import { GoogleSession, ReauthRequiredError } from "./google_auth.ts";
import { googleEventBody } from "./google_export.ts";
import { importGoogleEvent, type GoogleEvent } from "./google_import.ts";
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
import postgres from "npm:postgres@3.4.5";

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
    recorded_local_revision: row.recorded_local_revision ?? null,
    last_synced_revision: row.last_synced_revision,
    created_at: row.created_at,
    entity_label: row.entity_label ?? null,
    field_categories: row.field_categories ?? [],
    can_keep_local_push: row.can_keep_local_push === true,
    can_use_remote: row.can_use_remote !== false,
    blocked_reason: row.blocked_reason ?? null,
  };
}

export const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(value: string): boolean {
  return UUID_RE.test(value);
}

export function parseExpectedRevision(value: unknown): number | null {
  if (typeof value === "number" && Number.isInteger(value) && value >= 0) {
    return value;
  }
  if (typeof value === "string" && /^(0|[1-9]\d*)$/.test(value)) {
    return Number(value);
  }
  return null;
}

export function freezeLocalSnapshot(
  row: Record<string, unknown>,
): Record<string, unknown> {
  return Object.freeze(JSON.parse(JSON.stringify(row)) as Record<string, unknown>);
}

export async function listAllTopLevelBlocks(args: {
  token: string;
  pageId: string;
  fetchImpl: typeof fetch;
}): Promise<NotionBlock[]> {
  const blocks: NotionBlock[] = [];
  let cursor: string | null = null;
  do {
    const url = new URL(`https://api.notion.com/v1/blocks/${args.pageId}/children`);
    url.searchParams.set("page_size", "100");
    if (cursor) {
      url.searchParams.set("start_cursor", cursor);
    }
    const response = await args.fetchImpl(url.toString(), {
      headers: notionHeaders(args.token),
    });
    if (!response.ok) {
      throw new Error(`notion_list_${response.status}`);
    }
    const payload = await response.json() as {
      results?: NotionBlock[];
      has_more?: boolean;
      next_cursor?: string | null;
    };
    blocks.push(...(payload.results ?? []));
    cursor = payload.has_more ? payload.next_cursor ?? null : null;
  } while (cursor);
  return blocks;
}

export async function replaceExistingNotionPage(args: {
  token: string;
  entityType: string;
  externalId: string;
  row: Record<string, unknown> & { id: string };
  fetchImpl: typeof fetch;
}): Promise<{ updatedAt: string }> {
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
    const existing = await listAllTopLevelBlocks({
      token: args.token,
      pageId: args.externalId,
      fetchImpl: args.fetchImpl,
    });
    for (const block of existing) {
      const blockId = typeof block.id === "string" ? block.id : "";
      if (!blockId) {
        throw new Error("notion_list_malformed");
      }
      const deleted = await args.fetchImpl(`https://api.notion.com/v1/blocks/${blockId}`, {
        method: "DELETE",
        headers: notionHeaders(args.token),
      });
      if (!deleted.ok && deleted.status !== 404) {
        throw new Error(`notion_delete_${deleted.status}`);
      }
    }
    const children = notionBody(args.entityType, args.row);
    if (children.length > 0) {
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
    }
  }
  const verified = await fetchLiveNotion({
    token: args.token,
    entityType: args.entityType,
    externalId: args.externalId,
    currentRow: args.row,
    fetchImpl: args.fetchImpl,
  });
  if (verified.kind === "remote_deleted") {
    throw new Error("REMOTE_GONE");
  }
  if (verified.kind !== "equal") {
    throw new Error("PROVIDER_VERIFY_FAILED");
  }
  if (!verified.updatedAt) {
    throw new Error("PROVIDER_VERIFY_FAILED");
  }
  return { updatedAt: verified.updatedAt };
}

type SqlJson = Record<string, unknown>;

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
  let blocks: NotionBlock[] = [];
  if (args.entityType !== "inbox_items") {
    try {
      blocks = await listAllTopLevelBlocks({
        token: args.token,
        pageId: args.externalId,
        fetchImpl: args.fetchImpl,
      });
    } catch {
      return {
        kind: "fetch_failed",
        patch: {},
        remoteSnapshot: {},
        etag: null,
        updatedAt: null,
      };
    }
  }
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

export async function pushExistingGoogle(args: {
  session: GoogleSession;
  calendarId: string;
  externalId: string;
  row: Record<string, unknown> & { id: string };
  ifMatchEtag?: string | null;
}): Promise<{ etag: string | null; updatedAt: string | null }> {
  const url =
    `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(args.calendarId)}/events/${encodeURIComponent(args.externalId)}`;
  const body = googleEventBody(args.row, args.externalId);
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (args.ifMatchEtag) {
    headers["If-Match"] = args.ifMatchEtag;
  }
  const patched = await args.session.fetch(url, {
    method: "PATCH",
    headers,
    body: JSON.stringify(body),
  });
  if (patched.status === 404) {
    throw new Error("REMOTE_GONE");
  }
  if (patched.status === 412) {
    throw new Error("PROVIDER_VERSION_CONFLICT");
  }
  if (!patched.ok) {
    throw new Error(`google_patch_${patched.status}`);
  }
  const verified = await fetchLiveGoogle({
    session: args.session,
    calendarId: args.calendarId,
    externalId: args.externalId,
    currentRow: args.row,
  });
  if (verified.kind === "remote_deleted") {
    throw new Error("REMOTE_GONE");
  }
  if (verified.kind !== "equal") {
    throw new Error("PROVIDER_VERIFY_FAILED");
  }
  return { etag: verified.etag, updatedAt: verified.updatedAt };
}

function jsonArg(sql: ReturnType<typeof db>, value: Record<string, unknown>) {
  return sql.json(JSON.parse(JSON.stringify(value)));
}

export type ResolveHooks = {
  afterLockedSnapshot?: (row: Record<string, unknown>) => Promise<void>;
};

async function withResolverTransaction<T>(
  connectionId: string,
  fn: (tx: ReturnType<typeof db>) => Promise<T>,
): Promise<T> {
  const url = Deno.env.get("SUPABASE_DB_URL");
  if (!url) {
    throw new Error("SUPABASE_DB_URL is not configured");
  }
  // Dedicated session: inbound connection lock, then one transaction that
  // takes user_id:0 and holds the selected row through provider I/O + finish.
  const session = postgres(url, { prepare: false, max: 1 });
  try {
    await session`select pg_advisory_lock(hashtextextended(${connectionId}::text, 1))`;
    try {
      return await session.begin(
        async (tx) => await fn(tx as unknown as ReturnType<typeof db>),
      ) as T;
    } finally {
      await session`select pg_advisory_unlock(hashtextextended(${connectionId}::text, 1))`;
    }
  } finally {
    await session.end({ timeout: 5 });
  }
}

function providerError(code: string): {
  ok: false;
  result: string;
  error: { code: string };
  status: number;
} {
  return { ok: false, result: "error", error: { code }, status: 409 };
}

export async function resolveExternalConflict(args: {
  userId: string;
  conflictId: string;
  choice: ResolveChoice;
  expectedLocalRevision: number;
  fetchImpl?: typeof fetch;
  hooks?: ResolveHooks;
}): Promise<{ ok: boolean; result: string; error?: { code: string }; status?: number }> {
  const fetchImpl = args.fetchImpl ?? fetch;
  const lookupRows = await db()`
    select connection_id
      from public.external_sync_conflicts
     where id = ${args.conflictId}::uuid
       and user_id = ${args.userId}::uuid
     limit 1
  `;
  const connectionId = String(lookupRows[0]?.connection_id ?? "");
  if (!connectionId) {
    return { ok: false, result: "error", error: { code: "NOT_FOUND" }, status: 404 };
  }

  return await withResolverTransaction(connectionId, async (tx) => {
    const loaded = sqlResult(await tx`
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
    const currentRow = freezeLocalSnapshot(
      loaded.current_row as Record<string, unknown>,
    ) as Record<string, unknown> & { id: string };
    if (args.hooks?.afterLockedSnapshot) {
      await args.hooks.afterLockedSnapshot(currentRow);
    }
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
      const googleSession = new GoogleSession(
        connectionId,
        credential.bundle,
        credential.accessExpiresAt,
      );
      const calendarId = String(container.calendar_id ?? "primary");
      live = await fetchLiveGoogle({
        session: googleSession,
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
          const written = await replaceExistingNotionPage({
            token: credential.bundle.access_token,
            entityType,
            externalId,
            row: currentRow,
            fetchImpl,
          });
          etag = null;
          updatedAt = written.updatedAt;
        } else {
          const googleSession = new GoogleSession(
            connectionId,
            credential.bundle,
            credential.accessExpiresAt,
          );
          const written = await pushExistingGoogle({
            session: googleSession,
            calendarId: String(container.calendar_id ?? "primary"),
            externalId,
            row: currentRow,
            ifMatchEtag: live.etag,
          });
          etag = written.etag;
          updatedAt = written.updatedAt;
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : "";
        if (message === "REMOTE_GONE") {
          const gone = sqlResult(await tx`
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
        if (
          message === "PROVIDER_VERIFY_FAILED" ||
          message === "PROVIDER_VERSION_CONFLICT" ||
          message.startsWith("notion_") ||
          message.startsWith("google_")
        ) {
          return providerError(
            message === "PROVIDER_VERSION_CONFLICT"
              ? "PROVIDER_VERSION_CONFLICT"
              : message === "PROVIDER_VERIFY_FAILED"
              ? "PROVIDER_VERIFY_FAILED"
              : "PROVIDER_WRITE_FAILED",
          );
        }
        throw error;
      }
      const finished = sqlResult(await tx`
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
      const finished = sqlResult(await tx`
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
      const finished = sqlResult(await tx`
        select integrations.finish_conflict_use_remote(
          ${args.userId}::uuid,
          ${args.conflictId}::uuid,
          ${args.expectedLocalRevision}::bigint,
          ${"remote_deleted"},
          ${jsonArg(tx, {})}::jsonb,
          ${jsonArg(tx, live.remoteSnapshot)}::jsonb,
          ${etag},
          ${updatedAt}::timestamptz,
          ${false}
        ) as result
      `);
      return { ok: finished.result === "resolved_remote", result: String(finished.result) };
    }

    const mappedEqual = decision.action === "finish_use_remote_equal";
    const finished = sqlResult(await tx`
      select integrations.finish_conflict_use_remote(
        ${args.userId}::uuid,
        ${args.conflictId}::uuid,
        ${args.expectedLocalRevision}::bigint,
        ${"update"},
        ${jsonArg(tx, live.patch)}::jsonb,
        ${jsonArg(tx, live.remoteSnapshot)}::jsonb,
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
