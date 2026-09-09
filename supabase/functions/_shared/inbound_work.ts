import postgres from "npm:postgres@3.4.5";
import { db } from "./db.ts";

export type EnqueueResult = {
  enqueued: boolean;
  coalesced?: boolean;
  rerun_requested?: boolean;
  created?: boolean;
  status: string;
  id: string;
};

function jsonPayload(
  sql: ReturnType<typeof db>,
  payload?: Record<string, unknown>,
) {
  return sql.json(JSON.parse(JSON.stringify(payload ?? {})));
}

export async function withConnectionInboundLock<T>(
  connectionId: string,
  fn: () => Promise<T>,
): Promise<T> {
  const url = Deno.env.get("SUPABASE_DB_URL");
  if (!url) {
    throw new Error("SUPABASE_DB_URL is not configured");
  }
  // Dedicated session so pg_advisory_lock is not reentrant across overlapping
  // requests that share the max:1 query pool in db().
  const lockSql = postgres(url, { prepare: false, max: 1 });
  try {
    await lockSql`select pg_advisory_lock(hashtextextended(${connectionId}::text, 1))`;
    try {
      return await fn();
    } finally {
      await lockSql`select pg_advisory_unlock(hashtextextended(${connectionId}::text, 1))`;
    }
  } finally {
    await lockSql.end({ timeout: 5 });
  }
}

export async function enqueueInboundWork(args: {
  connectionId: string;
  provider: "notion" | "google";
  workType: string;
  dedupKey: string;
  payload?: Record<string, unknown>;
}): Promise<EnqueueResult> {
  const sql = db();
  const rows = await sql`
    select integrations.enqueue_inbound_work(
      ${args.connectionId}::uuid,
      ${args.provider},
      ${args.workType},
      ${args.dedupKey},
      ${jsonPayload(sql, args.payload)}::jsonb
    ) as result
  `;
  return rows[0].result as EnqueueResult;
}

export type AcceptEventResult = EnqueueResult & {
  accepted: boolean;
  duplicate: boolean;
};

export async function acceptInboundEvent(args: {
  provider: "notion" | "google";
  eventKey: string;
  connectionId: string;
  workType: string;
  dedupKey: string;
  payload?: Record<string, unknown>;
}): Promise<AcceptEventResult> {
  const sql = db();
  const rows = await sql`
    select integrations.accept_inbound_event(
      ${args.provider},
      ${args.eventKey},
      ${args.connectionId}::uuid,
      ${args.workType},
      ${args.dedupKey},
      ${jsonPayload(sql, args.payload)}::jsonb
    ) as result
  `;
  return rows[0].result as AcceptEventResult;
}

export async function recordInboundEvent(args: {
  provider: string;
  eventKey: string;
  connectionId: string | null;
  result: string;
}): Promise<boolean> {
  const rows = await db()`
    select integrations.record_inbound_event(
      ${args.provider},
      ${args.eventKey},
      ${args.connectionId},
      ${args.result}
    ) as inserted
  `;
  return Boolean(rows[0].inserted);
}

export async function claimInboundWork(): Promise<Record<string, unknown> | null> {
  const rows = await db()`
    select integrations.claim_inbound_work() as work
  `;
  return (rows[0]?.work ?? null) as Record<string, unknown> | null;
}

export async function claimInboundWorkOf(
  workTypes: string[],
): Promise<Record<string, unknown> | null> {
  const rows = await db()`
    select integrations.claim_inbound_work_of(${workTypes}::text[]) as work
  `;
  return (rows[0]?.work ?? null) as Record<string, unknown> | null;
}

export async function deferInboundWork(
  id: string,
  delay = "2 minutes",
): Promise<Record<string, unknown>> {
  const rows = await db()`
    select integrations.defer_inbound_work(${id}::uuid, ${delay}::interval) as result
  `;
  return rows[0].result as Record<string, unknown>;
}

export async function completeInboundWork(
  id: string,
  error: string | null = null,
): Promise<Record<string, unknown>> {
  const rows = await db()`
    select integrations.complete_inbound_work(${id}::uuid, ${error}) as result
  `;
  return rows[0].result as Record<string, unknown>;
}

export async function heartbeatInboundWork(
  id: string,
  extend = "3 minutes",
): Promise<Record<string, unknown>> {
  const rows = await db()`
    select integrations.heartbeat_inbound_work(${id}::uuid, ${extend}::interval) as result
  `;
  return rows[0].result as Record<string, unknown>;
}

export async function activateInbound(
  connectionId: string,
): Promise<Record<string, unknown>> {
  const rows = await db()`
    select integrations.activate_inbound(${connectionId}::uuid) as result
  `;
  return rows[0].result as Record<string, unknown>;
}

export async function deactivateInbound(
  connectionId: string,
): Promise<Record<string, unknown>> {
  const rows = await db()`
    select integrations.deactivate_inbound(${connectionId}::uuid) as result
  `;
  return rows[0].result as Record<string, unknown>;
}

export function startInboundWorkHeartbeat(
  workId: string,
  args?: {
    intervalMs?: number;
    heartbeat?: (id: string) => Promise<Record<string, unknown>>;
  },
): { stop: () => void; lost: () => boolean } {
  let lost = false;
  const heartbeat = args?.heartbeat ?? heartbeatInboundWork;
  const tick = async () => {
    try {
      const result = await heartbeat(workId);
      if (result.result !== "ok") {
        lost = true;
      }
    } catch {
      lost = true;
    }
  };
  const timer = setInterval(() => {
    void tick();
  }, args?.intervalMs ?? 30_000);
  void tick();
  return {
    stop: () => clearInterval(timer),
    lost: () => lost,
  };
}
