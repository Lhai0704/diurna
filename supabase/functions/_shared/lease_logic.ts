export const LEASE_MS = 180_000;

export type JsonObject = Record<string, unknown>;

export type LeaseRow = {
  sync_run_id: string | null;
  sync_lease_until: string | null;
  page_cursor: JsonObject;
  sync_start_generation: number | null;
  last_seen_generation: number | null;
  last_sync_status: string;
};

export type AcquireOk = {
  kind: "acquired";
  runId: string;
  pageCursor: JsonObject;
  syncStartGeneration: number | null;
  shortCircuit: boolean;
  patch: {
    sync_run_id: string;
    sync_lease_until: string;
    page_cursor: JsonObject;
    sync_start_generation: number | null;
  };
};

export type AcquireBusy = {
  kind: "in_progress";
  retryAfterSeconds: number;
};

export function isCursorEmpty(cursor: JsonObject | null | undefined): boolean {
  if (cursor == null) {
    return true;
  }
  return Object.keys(cursor).length === 0;
}

export function acquireLease(args: {
  now: Date;
  incomingRunId: string | null;
  currentGeneration: number;
  row: LeaseRow;
  newRunId: string;
}): AcquireOk | AcquireBusy {
  const leaseUntil = args.row.sync_lease_until
    ? Date.parse(args.row.sync_lease_until)
    : 0;
  const leaseValid = Number.isFinite(leaseUntil) && leaseUntil > args.now.getTime();
  const leaseIso = new Date(args.now.getTime() + LEASE_MS).toISOString();

  if (leaseValid) {
    if (
      args.incomingRunId != null &&
      args.row.sync_run_id != null &&
      args.incomingRunId === args.row.sync_run_id
    ) {
      return {
        kind: "acquired",
        runId: args.row.sync_run_id,
        pageCursor: args.row.page_cursor,
        syncStartGeneration: args.row.sync_start_generation,
        shortCircuit: false,
        patch: {
          sync_run_id: args.row.sync_run_id,
          sync_lease_until: leaseIso,
          page_cursor: args.row.page_cursor,
          sync_start_generation: args.row.sync_start_generation,
        },
      };
    }
    return {
      kind: "in_progress",
      retryAfterSeconds: Math.max(
        1,
        Math.ceil((leaseUntil - args.now.getTime()) / 1000),
      ),
    };
  }

  const cursorEmpty = isCursorEmpty(args.row.page_cursor);
  if (!cursorEmpty && args.row.sync_start_generation != null) {
    return {
      kind: "acquired",
      runId: args.newRunId,
      pageCursor: args.row.page_cursor,
      syncStartGeneration: args.row.sync_start_generation,
      shortCircuit: false,
      patch: {
        sync_run_id: args.newRunId,
        sync_lease_until: leaseIso,
        page_cursor: args.row.page_cursor,
        sync_start_generation: args.row.sync_start_generation,
      },
    };
  }

  const startGeneration = args.currentGeneration;
  const shortCircuit =
    cursorEmpty &&
    args.row.last_sync_status === "success" &&
    args.row.last_seen_generation === startGeneration;

  return {
    kind: "acquired",
    runId: args.newRunId,
    pageCursor: {},
    syncStartGeneration: startGeneration,
    shortCircuit,
    patch: {
      sync_run_id: args.newRunId,
      sync_lease_until: leaseIso,
      page_cursor: {},
      sync_start_generation: startGeneration,
    },
  };
}

export function finishPass(args: {
  startGeneration: number | null;
  endGeneration: number;
  hasErrorLinks: boolean;
}): { caughtUp: boolean } {
  if (args.hasErrorLinks) {
    return { caughtUp: false };
  }
  if (args.startGeneration == null) {
    return { caughtUp: false };
  }
  return { caughtUp: args.startGeneration === args.endGeneration };
}

export function settingsInvalidateShortCircuit(): {
  last_seen_generation: null;
  last_sync_status: "pending";
  page_cursor: JsonObject;
  sync_start_generation: null;
} {
  return {
    last_seen_generation: null,
    last_sync_status: "pending",
    page_cursor: {},
    sync_start_generation: null,
  };
}
