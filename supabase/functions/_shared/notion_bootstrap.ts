import { readCredential } from "./credentials.ts";
import { db } from "./db.ts";
import { loadConnectionRow, setInboundStatus } from "./connection_status.ts";
import {
  applyExternalChange,
  bootstrapLinkVersion,
  freezeLinkConflict,
} from "./external_mutation.ts";
import {
  importNotionPage,
  type NotionBlock,
  type NotionImportResult,
  type NotionPage,
} from "./notion_import.ts";
import {
  isLegacyMemoDiaryTitle,
  notionHeaders,
  patchNotionPageTitle,
} from "./notion_export.ts";
import { patchMatchesRow } from "./mapped.ts";

type NotionFetch = (input: string, init?: RequestInit) => Promise<Response>;

async function listBlockChildren(
  token: string,
  pageId: string,
  fetchImpl: NotionFetch,
): Promise<NotionBlock[]> {
  const blocks: NotionBlock[] = [];
  let cursor: string | null = null;
  do {
    const url = new URL(`https://api.notion.com/v1/blocks/${pageId}/children`);
    url.searchParams.set("page_size", "100");
    if (cursor) url.searchParams.set("start_cursor", cursor);
    const response = await fetchImpl(url.toString(), { headers: notionHeaders(token) });
    if (!response.ok) {
      throw new Error(`notion_blocks_${response.status}`);
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

async function loadEntityRow(
  entityType: string,
  entityId: string,
): Promise<Record<string, unknown> | null> {
  const result = entityType === "inbox_items"
    ? await db()`select * from public.inbox_items where id = ${entityId}::uuid`
    : entityType === "memos"
    ? await db()`select * from public.memos where id = ${entityId}::uuid`
    : await db()`select * from public.diary_entries where id = ${entityId}::uuid`;
  return (result[0] as Record<string, unknown> | undefined) ?? null;
}

export type NotionBootstrapDecision =
  | {
    action: "ready";
    imported: Extract<NotionImportResult, { kind: "update" }>;
  }
  | {
    action: "migrate_title";
    imported: Extract<NotionImportResult, { kind: "update" }>;
    remainingDrift: boolean;
  }
  | {
    action: "drift";
    imported: Extract<NotionImportResult, { kind: "update" }>;
  }
  | {
    action: "unsupported";
    imported: Extract<NotionImportResult, { kind: "unsupported_content" }>;
  }
  | {
    action: "remote_deleted";
    missing: boolean;
    lastEditedTime: string | null;
  };

export function decideNotionBootstrapPage(args: {
  entityType: string;
  page: NotionPage | null;
  blocks: NotionBlock[];
  entity: Record<string, unknown> | null;
}): NotionBootstrapDecision {
  if (!args.page) {
    return { action: "remote_deleted", missing: true, lastEditedTime: null };
  }
  const imported = importNotionPage({
    entityType: args.entityType,
    page: args.page,
    blocks: args.blocks,
    currentContent: args.entity && typeof args.entity.content === "string"
      ? args.entity.content
      : "",
  });
  if (imported.kind === "unsupported_content") {
    return { action: "unsupported", imported };
  }
  if (imported.kind === "remote_deleted") {
    return {
      action: "remote_deleted",
      missing: false,
      lastEditedTime: imported.lastEditedTime,
    };
  }
  const legacy = Boolean(
    args.entity &&
      isLegacyMemoDiaryTitle({
        entityType: args.entityType,
        localTitle: String(args.entity.title ?? ""),
        localContent: String(args.entity.content ?? ""),
        remoteTitle: String(imported.patch.title ?? ""),
      }),
  );
  if (legacy && args.entity) {
    const patch = { ...imported.patch, title: args.entity.title };
    return {
      action: "migrate_title",
      imported: { ...imported, patch },
      remainingDrift: !patchMatchesRow(args.entity, patch),
    };
  }
  const drift = !args.entity || !patchMatchesRow(args.entity, imported.patch);
  return {
    action: drift ? "drift" : "ready",
    imported,
  };
}

export async function bootstrapNotionConnection(args: {
  connectionId: string;
  fetchImpl?: NotionFetch;
}): Promise<{ result: string; ready: number; conflicts: number }> {
  const connection = await loadConnectionRow(args.connectionId);
  if (!connection || connection.status !== "connected") {
    return { result: "ignored", ready: 0, conflicts: 0 };
  }
  const latest = await loadConnectionRow(args.connectionId);
    if (!latest || latest.status !== "connected") {
      return { result: "ignored", ready: 0, conflicts: 0 };
    }
    await setInboundStatus(args.connectionId, "bootstrap_start");
    const credential = await readCredential(args.connectionId);
    if (!credential) {
      await setInboundStatus(args.connectionId, "reauth", { error: "REAUTH_REQUIRED" });
      throw new Error("REAUTH_REQUIRED");
    }
    const fetchImpl = args.fetchImpl ?? fetch;
    const links = await db()`
      select entity_type, entity_id::text as entity_id, external_id
        from public.external_sync_links
       where connection_id = ${args.connectionId}::uuid
         and entity_type in ('inbox_items', 'memos', 'diary_entries')
    ` as Array<{ entity_type: string; entity_id: string; external_id: string }>;

    let ready = 0;
    let conflicts = 0;
    for (const link of links) {
      const pageResponse = await fetchImpl(
        `https://api.notion.com/v1/pages/${link.external_id}`,
        { headers: notionHeaders(credential.bundle.access_token) },
      );
      if (pageResponse.status === 404) {
        const applied = await applyExternalChange({
          connectionId: args.connectionId,
          entityType: link.entity_type,
          entityId: link.entity_id,
          externalId: link.external_id,
          operation: "remote_deleted",
          patch: {},
          remoteSnapshot: { missing: true },
        });
        if (applied.result === "conflict") conflicts += 1;
        continue;
      }
      if (!pageResponse.ok) {
        throw new Error(`notion_page_${pageResponse.status}`);
      }
      const page = await pageResponse.json() as NotionPage;
      const entity = await loadEntityRow(link.entity_type, link.entity_id);
      const blocks = link.entity_type === "inbox_items"
        ? []
        : await listBlockChildren(credential.bundle.access_token, link.external_id, fetchImpl);
      const decision = decideNotionBootstrapPage({
        entityType: link.entity_type,
        page,
        blocks,
        entity,
      });
      if (decision.action === "unsupported") {
        await freezeLinkConflict({
          connectionId: args.connectionId,
          entityType: link.entity_type,
          entityId: link.entity_id,
          externalId: link.external_id,
          reason: "unsupported_content",
          remoteSnapshot: decision.imported.remoteSnapshot,
          providerUpdatedAt: decision.imported.lastEditedTime,
        });
        conflicts += 1;
        continue;
      }
      if (decision.action === "remote_deleted") {
        const applied = await applyExternalChange({
          connectionId: args.connectionId,
          entityType: link.entity_type,
          entityId: link.entity_id,
          externalId: link.external_id,
          operation: "remote_deleted",
          patch: {},
          remoteSnapshot: { missing: decision.missing },
          providerUpdatedAt: decision.lastEditedTime,
        });
        if (applied.result === "conflict") conflicts += 1;
        continue;
      }
      let providerUpdatedAt = decision.imported.lastEditedTime;
      if (decision.action === "migrate_title") {
        const migrated = await patchNotionPageTitle({
          token: credential.bundle.access_token,
          pageId: link.external_id,
          title: String(entity?.title ?? ""),
          fetchImpl,
        });
        providerUpdatedAt = migrated.lastEditedTime ?? providerUpdatedAt;
      }
      const bootstrapped = await bootstrapLinkVersion({
        connectionId: args.connectionId,
        entityType: link.entity_type,
        entityId: link.entity_id,
        externalId: link.external_id,
        providerUpdatedAt,
        drift: decision.action === "drift" ||
          (decision.action === "migrate_title" && decision.remainingDrift),
        reason: decision.action === "drift" ||
            (decision.action === "migrate_title" && decision.remainingDrift)
          ? "bootstrap_remote_drift"
          : undefined,
        localSnapshot: entity ?? {},
        remoteSnapshot: decision.imported.remoteSnapshot,
      });
      if (bootstrapped.result === "conflict") {
        conflicts += 1;
      } else {
        ready += 1;
      }
    }
  await setInboundStatus(args.connectionId, "bootstrap_ok_watch_ok", { result: "bootstrap" });
  return { result: "ok", ready, conflicts };
}
