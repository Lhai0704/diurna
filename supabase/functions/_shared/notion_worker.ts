import { loadConnectionRow } from "./connection_status.ts";
import { readCredential } from "./credentials.ts";
import { db } from "./db.ts";
import {
  applyExternalChange,
  freezeLinkConflict,
  restoreRemoteDeletedLink,
} from "./external_mutation.ts";
import {
  importNotionPage,
  type NotionBlock,
  type NotionPage,
} from "./notion_import.ts";
import { notionHeaders } from "./notion_export.ts";

export type NotionFetch = (
  input: string,
  init?: RequestInit,
) => Promise<Response>;

type LinkRow = {
  entity_type: string;
  entity_id: string;
  external_id: string;
  inbound_state: string;
};

async function loadLink(
  connectionId: string,
  pageId: string,
): Promise<LinkRow | null> {
  const rows = await db()`
    select entity_type, entity_id, external_id, inbound_state
      from public.external_sync_links
     where connection_id = ${connectionId}
       and external_id = ${pageId}
     limit 1
  `;
  return (rows[0] as LinkRow | undefined) ?? null;
}

async function currentContent(
  entityType: string,
  entityId: string,
): Promise<string | undefined> {
  if (entityType === "inbox_items") {
    const rows = await db()`select content from public.inbox_items where id = ${entityId}::uuid`;
    return rows[0]?.content as string | undefined;
  }
  if (entityType === "memos") {
    const rows = await db()`select content from public.memos where id = ${entityId}::uuid`;
    return rows[0]?.content as string | undefined;
  }
  if (entityType === "diary_entries") {
    const rows = await db()`select content from public.diary_entries where id = ${entityId}::uuid`;
    return rows[0]?.content as string | undefined;
  }
  return undefined;
}

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
    if (cursor) {
      url.searchParams.set("start_cursor", cursor);
    }
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

export async function processNotionPageWork(args: {
  connectionId: string;
  pageId: string;
  eventType: string;
  fetchImpl?: NotionFetch;
}): Promise<{ result: string; reason?: string }> {
  const fetchImpl = args.fetchImpl ?? fetch;
  const connection = await loadConnectionRow(args.connectionId);
  if (!connection || connection.status !== "connected") {
    return { result: "ignored", reason: "disconnected" };
  }
  const inboundStatus = String(connection.inbound_status ?? "disabled");
  if (inboundStatus === "disabled" || inboundStatus === "bootstrapping") {
    return { result: "deferred" };
  }
  if (inboundStatus === "error") {
    return { result: "ignored", reason: "error" };
  }
  const link = await loadLink(args.connectionId, args.pageId);
  if (!link) {
    return { result: "ignored", reason: "no_link" };
  }
  if (
    link.entity_type !== "inbox_items" &&
    link.entity_type !== "memos" &&
    link.entity_type !== "diary_entries"
  ) {
    return { result: "ignored", reason: "wrong_type" };
  }

  if (args.eventType === "page.deleted") {
    const applied = await applyExternalChange({
      connectionId: args.connectionId,
      entityType: link.entity_type,
      entityId: link.entity_id,
      externalId: link.external_id,
      operation: "remote_deleted",
      patch: {},
      remoteSnapshot: { page_id: args.pageId, event_type: args.eventType },
    });
    return { result: applied.result, reason: applied.reason };
  }

  if (args.eventType === "page.undeleted" && link.inbound_state === "remote_deleted") {
    const restored = await restoreRemoteDeletedLink({
      connectionId: args.connectionId,
      entityType: link.entity_type,
      entityId: link.entity_id,
      externalId: link.external_id,
    });
    if (restored.result === "conflict") {
      return { result: restored.result, reason: restored.reason };
    }
  }

  const credential = await readCredential(args.connectionId);
  if (!credential) {
    throw new Error("REAUTH_REQUIRED");
  }
  const pageResponse = await fetchImpl(
    `https://api.notion.com/v1/pages/${args.pageId}`,
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
      remoteSnapshot: { page_id: args.pageId, missing: true },
    });
    return { result: applied.result, reason: applied.reason };
  }
  if (!pageResponse.ok) {
    throw new Error(`notion_page_${pageResponse.status}`);
  }
  const page = await pageResponse.json() as NotionPage;
  const blocks = link.entity_type === "inbox_items"
    ? []
    : await listBlockChildren(
      credential.bundle.access_token,
      args.pageId,
      fetchImpl,
    );
  const imported = importNotionPage({
    entityType: link.entity_type,
    page,
    blocks,
    currentContent: await currentContent(link.entity_type, link.entity_id),
  });

  if (imported.kind === "remote_deleted") {
    const applied = await applyExternalChange({
      connectionId: args.connectionId,
      entityType: link.entity_type,
      entityId: link.entity_id,
      externalId: link.external_id,
      operation: "remote_deleted",
      patch: {},
      remoteSnapshot: imported,
      providerUpdatedAt: imported.lastEditedTime,
    });
    return { result: applied.result, reason: applied.reason };
  }

  if (imported.kind === "unsupported_content") {
    const frozen = await freezeLinkConflict({
      connectionId: args.connectionId,
      entityType: link.entity_type,
      entityId: link.entity_id,
      externalId: link.external_id,
      reason: "unsupported_content",
      remoteSnapshot: imported.remoteSnapshot,
      providerUpdatedAt: imported.lastEditedTime,
    });
    return { result: frozen.result, reason: frozen.reason };
  }

  const applied = await applyExternalChange({
    connectionId: args.connectionId,
    entityType: link.entity_type,
    entityId: link.entity_id,
    externalId: link.external_id,
    operation: "update",
    patch: imported.patch,
    remoteSnapshot: imported.remoteSnapshot,
    providerUpdatedAt: imported.lastEditedTime,
  });
  return { result: applied.result, reason: applied.reason };
}
