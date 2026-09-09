import { readCredential } from "./credentials.ts";
import { db } from "./db.ts";
import { loadConnectionRow, touchInboundOk } from "./connection_status.ts";
import { enqueueInboundWork } from "./inbound_work.ts";
import { notionHeaders } from "./notion_export.ts";

type NotionFetch = (input: string, init?: RequestInit) => Promise<Response>;

// Notion has no Calendar-style syncToken. Repair is a bounded last_edited_time
// query per connected data source, not a full page scan and not a true cursor:
// look back last_inbound_at - 5 minutes, at most 3 query pages (100 each) per
// source, then enqueue the same notion_page work as webhooks. Cadence is the
// worker's 15-minute repair interval for active/degraded connections.
const OVERLAP_MS = 5 * 60 * 1000;
const MAX_PAGES_PER_SOURCE = 3;

async function queryDataSource(args: {
  token: string;
  dataSourceId: string;
  sinceIso: string;
  fetchImpl: NotionFetch;
}): Promise<string[]> {
  const ids: string[] = [];
  let cursor: string | null = null;
  for (let page = 0; page < MAX_PAGES_PER_SOURCE; page++) {
    const response = await args.fetchImpl(
      `https://api.notion.com/v1/data_sources/${args.dataSourceId}/query`,
      {
        method: "POST",
        headers: notionHeaders(args.token),
        body: JSON.stringify({
          page_size: 100,
          start_cursor: cursor ?? undefined,
          filter: {
            timestamp: "last_edited_time",
            last_edited_time: { on_or_after: args.sinceIso },
          },
        }),
      },
    );
    if (!response.ok) {
      throw new Error(`notion_query_${response.status}`);
    }
    const payload = await response.json() as {
      results?: Array<{ id?: string }>;
      has_more?: boolean;
      next_cursor?: string | null;
    };
    for (const row of payload.results ?? []) {
      if (typeof row.id === "string") ids.push(row.id);
    }
    if (!payload.has_more || !payload.next_cursor) {
      break;
    }
    cursor = payload.next_cursor;
  }
  return ids;
}

export async function repairNotionConnection(args: {
  connectionId: string;
  now?: Date;
  fetchImpl?: NotionFetch;
}): Promise<{ result: string; enqueued: number }> {
  const connection = await loadConnectionRow(args.connectionId);
  if (!connection || connection.status !== "connected") {
    return { result: "ignored", enqueued: 0 };
  }
  const inboundStatus = String(connection.inbound_status ?? "");
  if (inboundStatus !== "active" && inboundStatus !== "degraded") {
    return { result: "deferred", enqueued: 0 };
  }
  const credential = await readCredential(args.connectionId);
  if (!credential) {
    throw new Error("REAUTH_REQUIRED");
  }
  const container = (connection.container ?? {}) as Record<string, string>;
  const lastInbound = connection.last_inbound_at
    ? Date.parse(String(connection.last_inbound_at))
    : NaN;
  const now = args.now ?? new Date();
  const since = new Date(
    (Number.isFinite(lastInbound) ? lastInbound : now.getTime() - 60 * 60 * 1000) - OVERLAP_MS,
  );
  const sinceIso = since.toISOString();
  const fetchImpl = args.fetchImpl ?? fetch;
  const sources = ["inbox_ds", "memo_ds", "diary_ds"]
    .map((key) => container[key])
    .filter((id): id is string => typeof id === "string" && id.length > 0);
  const pageIds = new Set<string>();
  for (const dataSourceId of sources) {
    const ids = await queryDataSource({
      token: credential.bundle.access_token,
      dataSourceId,
      sinceIso,
      fetchImpl,
    });
    for (const id of ids) pageIds.add(id);
  }
  const linked = pageIds.size === 0 ? [] : await db()`
    select external_id
      from public.external_sync_links
     where connection_id = ${args.connectionId}::uuid
       and external_id = any(${[...pageIds]}::text[])
  `;
  let enqueued = 0;
  for (const row of linked) {
    await enqueueInboundWork({
      connectionId: args.connectionId,
      provider: "notion",
      workType: "notion_page",
      dedupKey: String(row.external_id),
      payload: {
        page_id: row.external_id,
        event_type: "page.properties_updated",
        source: "repair",
      },
    });
    enqueued += 1;
  }
  await touchInboundOk(args.connectionId, "repair");
  return { result: "ok", enqueued };
}
