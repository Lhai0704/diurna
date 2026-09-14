import { db } from "./db.ts";
import {
  acquireLease,
  type JsonObject,
  type LeaseRow,
} from "./lease_logic.ts";

export async function acquireConnectionLease(args: {
  connectionId: string;
  userId: string;
  incomingRunId: string | null;
  currentGeneration: number;
}): Promise<
  | { kind: "missing" }
  | { kind: "in_progress"; retryAfterSeconds: number }
  | {
      kind: "acquired";
      runId: string;
      pageCursor: JsonObject;
      syncStartGeneration: number | null;
      shortCircuit: boolean;
    }
> {
  const sql = db();
  return await sql.begin(async (tx) => {
    const rows = await tx`
      select sync_run_id, sync_lease_until, page_cursor, sync_start_generation,
             last_seen_generation, last_sync_status
        from public.integration_connections
       where id = ${args.connectionId}
         and user_id = ${args.userId}
         for update
    `;
    if (rows.length === 0) {
      return { kind: "missing" as const };
    }
    const row = rows[0] as LeaseRow;
    const decision = acquireLease({
      now: new Date(),
      incomingRunId: args.incomingRunId,
      currentGeneration: args.currentGeneration,
      newRunId: crypto.randomUUID(),
      row: {
        ...row,
        page_cursor: (row.page_cursor ?? {}) as JsonObject,
      },
    });
    if (decision.kind === "in_progress") {
      return decision;
    }
    await tx`
      update public.integration_connections
         set sync_run_id = ${decision.patch.sync_run_id},
             sync_lease_until = ${decision.patch.sync_lease_until},
             page_cursor = ${sql.json(JSON.parse(JSON.stringify(decision.patch.page_cursor)))},
             sync_start_generation = ${decision.patch.sync_start_generation},
             updated_at = now()
       where id = ${args.connectionId}
         and user_id = ${args.userId}
    `;
    return {
      kind: "acquired" as const,
      runId: decision.runId,
      pageCursor: decision.pageCursor,
      syncStartGeneration: decision.syncStartGeneration,
      shortCircuit: decision.shortCircuit,
    };
  });
}

export async function persistLeaseProgress(args: {
  connectionId: string;
  userId: string;
  runId: string;
  pageCursor: JsonObject;
  lastSyncStatus: string;
  lastSyncSummary: JsonObject;
  lastError: string | null;
  lastSeenGeneration: number | null;
  clearLease: boolean;
  syncStartGeneration: number | null;
}): Promise<void> {
  const sql = db();
  await sql.begin(async (tx) => {
    const rows = await tx`
      select sync_run_id
        from public.integration_connections
       where id = ${args.connectionId}
         and user_id = ${args.userId}
         for update
    `;
    if (rows.length === 0 || rows[0].sync_run_id !== args.runId) {
      return;
    }
    if (args.clearLease) {
      await tx`
        update public.integration_connections
           set sync_run_id = null,
               sync_lease_until = null,
               page_cursor = '{}'::jsonb,
               last_sync_status = ${args.lastSyncStatus},
               last_sync_summary = ${sql.json(JSON.parse(JSON.stringify(args.lastSyncSummary)))},
               last_error = ${args.lastError},
               last_sync_at = now(),
               last_seen_generation = ${args.lastSeenGeneration},
               sync_start_generation = null,
               updated_at = now()
         where id = ${args.connectionId}
           and user_id = ${args.userId}
           and sync_run_id = ${args.runId}
      `;
      return;
    }
    await tx`
      update public.integration_connections
         set page_cursor = ${sql.json(JSON.parse(JSON.stringify(args.pageCursor)))},
             sync_lease_until = now() + interval '180 seconds',
             last_sync_status = ${args.lastSyncStatus},
             last_sync_summary = ${sql.json(JSON.parse(JSON.stringify(args.lastSyncSummary)))},
             last_error = ${args.lastError},
             last_sync_at = now(),
             sync_start_generation = ${args.syncStartGeneration},
             updated_at = now()
       where id = ${args.connectionId}
         and user_id = ${args.userId}
         and sync_run_id = ${args.runId}
    `;
  });
}
