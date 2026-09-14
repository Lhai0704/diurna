import { readCredential } from "./credentials.ts";
import { db } from "./db.ts";
import { loadConnectionRow, touchInboundOk } from "./connection_status.ts";
import { enqueueInboundWork } from "./inbound_work.ts";
import { queryDataSource, discoverNotionPages } from "./notion_discovery.ts";
import { notionId } from "./remote_identity.ts";
export { MAX_PAGES_PER_SOURCE } from "./notion_discovery.ts";

type NotionFetch = (input: string, init?: RequestInit) => Promise<Response>;

// Notion has no Calendar-style syncToken. Repair is a bounded last_edited_time
// query per connected data source, not a full page scan and not a true cursor:
// look back last_inbound_at - 5 minutes, at most 3 query pages (100 each) per
// source, then enqueue the same notion_page work as webhooks. Cadence is the
// worker's 15-minute repair interval for active/degraded connections.
const OVERLAP_MS = 5 * 60 * 1000;


export type RepairSourceState = {
  sinceIso: string;
  cursor: string | null;
};

export type RepairState = Record<string, RepairSourceState>;

export function mergeRepairState(args: {
  previous: RepairState;
  sourceId: string;
  sinceIso: string;
  hasMore: boolean;
  nextCursor: string | null;
}): RepairState {
  const next = { ...args.previous };
  if (args.hasMore && args.nextCursor) {
    next[args.sourceId] = { sinceIso: args.sinceIso, cursor: args.nextCursor };
  } else {
    delete next[args.sourceId];
  }
  return next;
}

export function shouldAdvanceRepairWatermark(state: RepairState): boolean {
  return Object.keys(state).length === 0;
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
  if (inboundStatus === "disabled") {
    return { result: "ignored", enqueued: 0 };
  }
  if (inboundStatus !== "active" && inboundStatus !== "degraded") {
    return { result: "deferred", enqueued: 0 };
  }
  const credential = await readCredential(args.connectionId);
  if (!credential) {
    throw new Error("REAUTH_REQUIRED");
  }
  const container = (connection.container ?? {}) as Record<string, string>;
  const complete = await discoverNotionPages({connectionId:args.connectionId,container,token:credential.bundle.access_token,fetchImpl:args.fetchImpl ?? fetch});
  if (!complete) return {result:"deferred",enqueued:0};
  const latest = await loadConnectionRow(args.connectionId);
  const previousState = (latest?.inbound_repair_state ?? {}) as RepairState;
  const lastInbound = connection.last_inbound_at
    ? Date.parse(String(connection.last_inbound_at))
    : NaN;
  const now = args.now ?? new Date();
  const defaultSince = new Date(
    (Number.isFinite(lastInbound) ? lastInbound : now.getTime() - 60 * 60 * 1000) - OVERLAP_MS,
  );
  const fetchImpl = args.fetchImpl ?? fetch;
  const sources = ["inbox_ds", "memo_ds", "diary_ds"]
    .map((key) => container[key])
    .filter((id): id is string => typeof id === "string" && id.length > 0)
    .map(notionId);
  const pageIds = new Set<string>();
  let nextState: RepairState = { ...previousState };
  for (const dataSourceId of sources) {
    const prior = previousState[dataSourceId];
    const sinceIso = prior?.sinceIso ?? defaultSince.toISOString();
    const listed = await queryDataSource({
      token: credential.bundle.access_token,
      dataSourceId,
      sinceIso,
      startCursor: prior?.cursor ?? null,
      fetchImpl,
    });
    for (const id of listed.ids) pageIds.add(id);
    nextState = mergeRepairState({
      previous: nextState,
      sourceId: dataSourceId,
      sinceIso,
      hasMore: listed.hasMore,
      nextCursor: listed.nextCursor,
    });
  }
  const pending = await db()`select s.external_id from integrations.remote_object_status s
    join public.external_sync_links l using(connection_id,external_id)
    where s.connection_id=${args.connectionId}::uuid and s.metadata_pending and l.inbound_state='ready'`;
  for (const row of pending) pageIds.add(String(row.external_id));
  let enqueued = 0;
  for (const pageId of pageIds) {
    await enqueueInboundWork({
      connectionId: args.connectionId,
      provider: "notion",
      workType: "notion_page",
      dedupKey: pageId,
      payload: {
        page_id: pageId,
        event_type: "page.properties_updated",
        source: "repair",
      },
    });
    enqueued += 1;
  }
  const sql = db();
  await sql`
    update public.integration_connections
       set inbound_repair_state = ${sql.json(JSON.parse(JSON.stringify(nextState)))}::jsonb,
           updated_at = now()
     where id = ${args.connectionId}::uuid
  `;
  if (shouldAdvanceRepairWatermark(nextState)) {
    await touchInboundOk(args.connectionId, "repair");
  }
  return { result: "ok", enqueued };
}
