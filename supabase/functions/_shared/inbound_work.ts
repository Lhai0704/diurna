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
  const sql = db();
  await sql`select pg_advisory_lock(hashtextextended(${connectionId}::text, 1))`;
  try {
    return await fn();
  } finally {
    await sql`select pg_advisory_unlock(hashtextextended(${connectionId}::text, 1))`;
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
