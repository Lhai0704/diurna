import { db } from "./db.ts";
import { notionHeaders } from "./notion_export.ts";
import { notionId } from "./remote_identity.ts";
import { processNotionPageWork } from "./notion_worker.ts";

type Fetch = (url: string, init?: RequestInit) => Promise<Response>;
export const MAX_PAGES_PER_SOURCE = 3;

export async function queryDataSource(
  args: {
    token: string;
    dataSourceId: string;
    sinceIso?: string;
    startCursor?: string | null;
    fetchImpl: Fetch;
  },
): Promise<{ ids: string[]; hasMore: boolean; nextCursor: string | null }> {
  const ids: string[] = [];
  let cursor = args.startCursor ?? null;
  for (let page = 0; page < MAX_PAGES_PER_SOURCE; page++) {
    const response = await args.fetchImpl(
      `https://api.notion.com/v1/data_sources/${args.dataSourceId}/query`,
      {
        method: "POST",
        headers: notionHeaders(args.token),
        body: JSON.stringify({
          page_size: 100,
          start_cursor: cursor ?? undefined,
          filter: args.sinceIso
            ? {
              timestamp: "last_edited_time",
              last_edited_time: { on_or_after: args.sinceIso },
            }
            : undefined,
        }),
      },
    );
    if (!response.ok) throw new Error(`notion_query_${response.status}`);
    const payload = await response.json() as {
      results?: Array<{ id?: string }>;
      has_more?: boolean;
      next_cursor?: string | null;
    };
    for (const row of payload.results ?? []) {
      if (row.id) ids.push(notionId(row.id));
    }
    if (payload.has_more && !payload.next_cursor) {
      throw new Error("notion_query_missing_cursor");
    }
    cursor = payload.has_more ? payload.next_cursor! : null;
    if (!cursor) break;
  }
  return { ids, hasMore: cursor !== null, nextCursor: cursor };
}

/** Persist progress only AFTER reconciliation: a crash replays the same batch. */
export async function discoverNotionPages(
  args: {
    connectionId: string;
    container: Record<string, unknown>;
    token: string;
    fetchImpl: Fetch;
    bootstrap?: boolean;
  },
): Promise<boolean> {
  let complete = true;
  for (const key of ["inbox_ds", "memo_ds", "diary_ds"]) {
    if (typeof args.container[key] !== "string") continue;
    const sourceId = notionId(args.container[key] as string);
    const sql = db();
    await sql`insert into integrations.remote_discovery_state(connection_id,source_id)
      values(${args.connectionId}::uuid,${sourceId}) on conflict do nothing`;
    const [state] = await sql`select * from integrations.remote_discovery_state
      where connection_id=${args.connectionId}::uuid and source_id=${sourceId}`;
    if (state.completed) continue;
    const batch = await queryDataSource({
      token: args.token,
      dataSourceId: sourceId,
      startCursor: state.cursor,
      fetchImpl: args.fetchImpl,
    });
    for (const pageId of batch.ids) {
      await processNotionPageWork({
        connectionId: args.connectionId,
        pageId,
        eventType: "page.created",
        fetchImpl: args.fetchImpl,
        bootstrap: args.bootstrap,
      });
    }
    await sql.begin(async (tx) => {
      // Catch-up watermark and completion must commit together, including on retry.
      if (!batch.hasMore) {
        const sinceIso = new Date(
          new Date(state.started_at).getTime() - 300_000,
        ).toISOString();
        const catchup = { [sourceId]: { sinceIso, cursor: null } };
        await tx`update public.integration_connections set inbound_repair_state=inbound_repair_state || ${
          tx.json(catchup)
        }::jsonb
          where id=${args.connectionId}::uuid`;
      }
      await tx`update integrations.remote_discovery_state set cursor=${batch.nextCursor},completed=${!batch
        .hasMore}
        where connection_id=${args.connectionId}::uuid and source_id=${sourceId}`;
    });
    if (batch.hasMore) complete = false;
  }
  return complete;
}

export async function beginNotionBootstrapDiscovery(
  connectionId: string,
): Promise<void> {
  const sql = db();
  await sql.begin(async (tx) => {
    const inserted =
      await tx`insert into integrations.remote_discovery_state(connection_id,source_id)
      values(${connectionId}::uuid,'__bootstrap__') on conflict do nothing returning source_id`;
    if (inserted.length) {
      await tx`update integrations.remote_discovery_state set cursor=null,completed=false,started_at=now()
      where connection_id=${connectionId}::uuid and source_id<>'__bootstrap__'`;
    }
  });
}

export async function finishNotionBootstrapDiscovery(
  connectionId: string,
): Promise<void> {
  await db().begin(async (tx) => {
    await tx`update public.integration_connections set inbound_status='active',last_inbound_result='bootstrap',
      last_inbound_at=now(),updated_at=now() where id=${connectionId}::uuid and status='connected' and inbound_status='bootstrapping'`;
    await tx`delete from integrations.remote_discovery_state where connection_id=${connectionId}::uuid and source_id='__bootstrap__'`;
  });
}
