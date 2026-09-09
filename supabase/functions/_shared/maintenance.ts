import { readCredential } from "./credentials.ts";
import { db } from "./db.ts";
import { GoogleSession } from "./google_auth.ts";
import { retryRetiringStops } from "./google_watch.ts";
import { enqueueInboundWork } from "./inbound_work.ts";
import {
  INBOUND_EVENT_TTL_HOURS,
  shouldEnqueueRepair,
  shouldRenewWatch,
} from "./mapped.ts";

export const WORK_TYPES = [
  "bootstrap_notion",
  "bootstrap_google",
  "notion_page",
  "google_incremental",
  "google_calendar_gone",
  "renew_watch",
  "repair",
] as const;

export async function purgeOldInboundEvents(): Promise<number> {
  const rows = await db()`
    select integrations.purge_inbound_events(interval '48 hours') as n
  `;
  return Number(rows[0]?.n ?? 0);
}

export async function enqueueDueBootstraps(): Promise<number> {
  const rows = await db()`
    select id::text as id, provider
      from integrations.due_inbound_bootstraps()
  `;
  let n = 0;
  for (const row of rows) {
    const provider = row.provider as "notion" | "google";
    await enqueueInboundWork({
      connectionId: String(row.id),
      provider,
      workType: provider === "google" ? "bootstrap_google" : "bootstrap_notion",
      dedupKey: String(row.id),
    });
    n += 1;
  }
  return n;
}

export async function enqueueDueRenewals(now = new Date()): Promise<number> {
  const rows = await db()`
    select distinct on (w.connection_id)
           w.connection_id::text as connection_id, w.expires_at, w.status,
           exists(
             select 1 from integrations.provider_watches c
              where c.connection_id = w.connection_id and c.status = 'creating'
           ) as has_creating
      from integrations.provider_watches w
      join public.integration_connections conn on conn.id = w.connection_id
     where w.status = 'active'
       and conn.status = 'connected'
       and conn.provider = 'google'
       and conn.inbound_status in ('active', 'degraded')
     order by w.connection_id, w.created_at desc
  `;
  const missing = await db()`
    select c.id::text as connection_id
      from public.integration_connections c
     where c.status = 'connected'
       and c.provider = 'google'
       and c.inbound_status = 'degraded'
       and not exists (
         select 1 from integrations.provider_watches w
          where w.connection_id = c.id
            and w.status in ('creating', 'active')
       )
  `;
  let n = 0;
  const enqueue = async (connectionId: string) => {
    await enqueueInboundWork({
      connectionId,
      provider: "google",
      workType: "renew_watch",
      dedupKey: connectionId,
    });
    n += 1;
  };
  for (const row of rows) {
    if (
      !shouldRenewWatch({
        now,
        expiresAt: row.expires_at ? String(row.expires_at) : null,
        status: String(row.status),
        hasCreating: Boolean(row.has_creating),
      })
    ) {
      continue;
    }
    await enqueue(String(row.connection_id));
  }
  for (const row of missing) {
    await enqueue(String(row.connection_id));
  }
  return n;
}

export async function enqueueDueRepairs(now = new Date()): Promise<number> {
  const rows = await db()`
    select id::text as id, provider, inbound_status, last_inbound_at,
           inbound_repair_state
      from public.integration_connections
     where status = 'connected'
       and inbound_status in ('active', 'degraded')
  `;
  let n = 0;
  for (const row of rows) {
    if (
      !shouldEnqueueRepair({
        now,
        lastInboundAt: row.last_inbound_at ? String(row.last_inbound_at) : null,
        inboundStatus: String(row.inbound_status),
        hasRepairState: row.inbound_repair_state != null &&
          typeof row.inbound_repair_state === "object" &&
          Object.keys(row.inbound_repair_state as object).length > 0,
      })
    ) {
      continue;
    }
    const provider = row.provider as "notion" | "google";
    if (provider === "google") {
      await enqueueInboundWork({
        connectionId: String(row.id),
        provider: "google",
        workType: "google_incremental",
        dedupKey: String(row.id),
        payload: { source: "repair" },
      });
    } else {
      await enqueueInboundWork({
        connectionId: String(row.id),
        provider: "notion",
        workType: "repair",
        dedupKey: String(row.id),
        payload: { source: "repair" },
      });
    }
    n += 1;
  }
  return n;
}

export async function runMaintenance(now = new Date()): Promise<{
  purged: number;
  bootstraps: number;
  renewals: number;
  repairs: number;
}> {
  const purged = await purgeOldInboundEvents();
  await retryRetiringStops({
    now,
    sessionFor: async (connectionId) => {
      const credential = await readCredential(connectionId);
      if (!credential) {
        return null;
      }
      return new GoogleSession(
        connectionId,
        credential.bundle,
        credential.accessExpiresAt,
      );
    },
  });
  const bootstraps = await enqueueDueBootstraps();
  const renewals = await enqueueDueRenewals(now);
  const repairs = await enqueueDueRepairs(now);
  return { purged, bootstraps, renewals, repairs };
}

export function inboundEventTtlHours(): number {
  return INBOUND_EVENT_TTL_HOURS;
}
