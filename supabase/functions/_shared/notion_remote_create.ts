import { db } from "./db.ts";
import { notionHeaders, omitLegacyRemoteTitle } from "./notion_export.ts";
import {
  importNotionPage,
  type NotionBlock,
  notionBodyIsLossless,
  type NotionPage,
} from "./notion_import.ts";
import { diurnaId, notionId, validDate } from "./remote_identity.ts";
import {
  reconcileExternalObject,
  type ReconcileInput,
  type ReconcileResult,
  recordRemoteReason,
} from "./remote_create.ts";

type Fetch = (url: string, init?: RequestInit) => Promise<Response>;
export function notionEntityType(
  container: Record<string, unknown>,
  sourceId: string,
): string | null {
  const entries = [["inbox_ds", "inbox_items"], ["memo_ds", "memos"], [
    "diary_ds",
    "diary_entries",
  ]];
  const matches = entries.filter(([key]) =>
    typeof container[key] === "string" &&
    notionId(container[key] as string) === notionId(sourceId)
  );
  return matches.length === 1 ? matches[0][1] : null;
}

export async function resolveNotionSource(
  page: NotionPage,
  container: Record<string, unknown>,
  token: string,
  fetchImpl: Fetch,
): Promise<string | null> {
  const parent = page.parent;
  if (parent?.type === "data_source_id" && parent.data_source_id) {
    return notionEntityType(container, parent.data_source_id)
      ? notionId(parent.data_source_id)
      : null;
  }
  if (parent?.type !== "database_id" || !parent.database_id) return null;
  const response = await fetchImpl(
    `https://api.notion.com/v1/databases/${parent.database_id}`,
    { headers: notionHeaders(token) },
  );
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`notion_database_${response.status}`);
  const payload = await response.json() as {
    data_sources?: Array<{ id: string }>;
  };
  // A legacy database parent is unambiguous only when it has a single source.
  const sources = payload.data_sources ?? [];
  return sources.length === 1 && notionEntityType(container, sources[0].id)
    ? notionId(sources[0].id)
    : null;
}

export function notionDiurnaId(page: NotionPage): string | null {
  const property = page.properties?.["Diurna ID"] as {
    rich_text?: Array<{ plain_text?: string; text?: { content?: string } }>;
  } | undefined;
  return diurnaId(
    property?.rich_text?.map((p) => p.plain_text ?? p.text?.content ?? "").join(
      "",
    ),
  );
}

export async function reconcileUnlinkedNotionPage(args: {
  connectionId: string;
  sourceId: string;
  entityType: string;
  page: NotionPage;
  blocks: NotionBlock[];
  recoveryEntity?: { title: string; content: string } | null;
  reconcile?: (input: ReconcileInput) => Promise<ReconcileResult>;
}): Promise<ReconcileResult> {
  if (args.page.archived || args.page.in_trash) {
    return { result: "ignored", reason: "remote_deleted" };
  }
  // Inbox has no body field. Even supported paragraphs there cannot be discarded.
  if (
    (args.entityType === "inbox_items" && args.blocks.length > 0) ||
    !notionBodyIsLossless(args.blocks)
  ) {
    if (!args.recoveryEntity) {
      return { result: "ignored", reason: "unsupported_content" };
    }
    return await (args.reconcile ?? reconcileExternalObject)({
      connectionId: args.connectionId,
      provider: "notion",
      containerId: args.sourceId,
      entityType: args.entityType,
      externalId: notionId(args.page.id!),
      candidateId: notionDiurnaId(args.page),
      patch: {},
      remoteSnapshot: { unsupported_body: true },
      providerUpdatedAt: args.page.last_edited_time ?? null,
      unsupportedReason: "unsupported_content",
    });
  }
  const imported = importNotionPage({
    entityType: args.entityType,
    page: args.page,
    blocks: args.blocks,
    currentContent: args.recoveryEntity?.content,
  });
  if (imported.kind !== "update") {
    return { result: "ignored", reason: imported.kind };
  }
  if (
    imported.patch.entry_date != null && !validDate(imported.patch.entry_date)
  ) return { result: "ignored", reason: "invalid_date" };
  return await (args.reconcile ?? reconcileExternalObject)({
    connectionId: args.connectionId,
    provider: "notion",
    containerId: args.sourceId,
    entityType: args.entityType,
    externalId: notionId(args.page.id!),
    candidateId: notionDiurnaId(args.page),
    patch: args.recoveryEntity
      ? omitLegacyRemoteTitle({
        entityType: args.entityType,
        localTitle: args.recoveryEntity.title,
        localContent: args.recoveryEntity.content,
        patch: imported.patch,
      })
      : imported.patch,
    remoteSnapshot: imported.remoteSnapshot,
    providerUpdatedAt: imported.lastEditedTime,
  });
}

export async function loadNotionRecoveryEntity(
  userId: string,
  entityType: string,
  candidateId: string | null,
): Promise<{ title: string; content: string } | null> {
  if (!candidateId) return null;
  const sql = db();
  const rows = entityType === "inbox_items"
    ? await sql`select '' as title,content from public.inbox_items where id=${candidateId}::uuid and user_id=${userId}::uuid`
    : entityType === "memos"
    ? await sql`select title,content from public.memos where id=${candidateId}::uuid and user_id=${userId}::uuid`
    : await sql`select title,content from public.diary_entries where id=${candidateId}::uuid and user_id=${userId}::uuid`;
  return rows[0]
    ? { title: String(rows[0].title), content: String(rows[0].content) }
    : null;
}

export async function retryNotionMetadata(
  connectionId: string,
  pageId: string,
  token: string,
  fetchImpl: Fetch,
): Promise<void> {
  const rows =
    await db()`select l.entity_id,l.last_synced_revision from integrations.remote_object_status s
    join public.external_sync_links l using(connection_id,external_id)
    join public.integration_connections c on c.id=l.connection_id
    where s.connection_id=${connectionId}::uuid and s.external_id=${pageId} and s.metadata_pending
      and c.status='connected' and c.inbound_status in ('active','degraded','bootstrapping')
      and l.provider='notion' and l.inbound_state='ready'`;
  if (!rows[0]) return;
  const response = await fetchImpl(
    `https://api.notion.com/v1/pages/${pageId}`,
    {
      method: "PATCH",
      headers: notionHeaders(token),
      body: JSON.stringify({
        properties: {
          "Diurna ID": {
            rich_text: [{
              type: "text",
              text: { content: String(rows[0].entity_id) },
            }],
          },
          Revision: { number: Number(rows[0].last_synced_revision) },
        },
      }),
    },
  );
  if (!response.ok) {
    await recordRemoteReason(connectionId, pageId, "metadata_writeback_failed");
    throw new Error(`notion_metadata_${response.status}`);
  }
  // Do not advance external_updated_at here: a concurrent user edit could be
  // included in the PATCH response. The following fetch must compare its body.
  await db()`update integrations.remote_object_status set metadata_pending=false,reason=null,updated_at=now()
    where connection_id=${connectionId}::uuid and external_id=${pageId}`;
}

export async function acknowledgeNotionCreateEcho(
  connectionId: string,
  pageId: string,
  patch: Record<string, unknown>,
  updatedAt: string | null,
): Promise<boolean> {
  const sql = db();
  const rows =
    await sql`select integrations.ack_remote_create_echo(${connectionId}::uuid,${pageId},
    ${
      sql.json(JSON.parse(JSON.stringify(patch)))
    }::jsonb,${updatedAt}::timestamptz) as acknowledged`;
  return rows[0].acknowledged === true;
}
