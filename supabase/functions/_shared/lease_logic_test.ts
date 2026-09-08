import {
  assertEquals,
  assert,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  acquireLease,
  finishPass,
  settingsInvalidateShortCircuit,
  type LeaseRow,
} from "./lease_logic.ts";

const emptyRow = (overrides: Partial<LeaseRow> = {}): LeaseRow => ({
  sync_run_id: null,
  sync_lease_until: null,
  page_cursor: {},
  sync_start_generation: null,
  last_seen_generation: null,
  last_sync_status: "never",
  ...overrides,
});

Deno.test("same run_id resumes while lease is valid", () => {
  const now = new Date("2026-09-08T12:00:00Z");
  const result = acquireLease({
    now,
    incomingRunId: "run-a",
    currentGeneration: 5,
    newRunId: "run-b",
    row: emptyRow({
      sync_run_id: "run-a",
      sync_lease_until: "2026-09-08T12:02:00Z",
      page_cursor: { inbox_items: "mid" },
      sync_start_generation: 3,
    }),
  });
  assertEquals(result.kind, "acquired");
  if (result.kind === "acquired") {
    assertEquals(result.runId, "run-a");
    assertEquals(result.syncStartGeneration, 3);
    assertEquals(result.pageCursor, { inbox_items: "mid" });
    assertEquals(result.shortCircuit, false);
  }
});

Deno.test("other run_id is rejected while lease is valid", () => {
  const now = new Date("2026-09-08T12:00:00Z");
  const result = acquireLease({
    now,
    incomingRunId: null,
    currentGeneration: 5,
    newRunId: "run-b",
    row: emptyRow({
      sync_run_id: "run-a",
      sync_lease_until: "2026-09-08T12:02:00Z",
      sync_start_generation: 3,
    }),
  });
  assertEquals(result.kind, "in_progress");
});

Deno.test("crash resume keeps original start generation and cursor", () => {
  const now = new Date("2026-09-08T12:00:00Z");
  const result = acquireLease({
    now,
    incomingRunId: null,
    currentGeneration: 101,
    newRunId: "run-b",
    row: emptyRow({
      sync_run_id: "run-a",
      sync_lease_until: "2026-09-08T11:00:00Z",
      page_cursor: { inbox_items: "M" },
      sync_start_generation: 100,
      last_sync_status: "partial",
    }),
  });
  assertEquals(result.kind, "acquired");
  if (result.kind === "acquired") {
    assertEquals(result.runId, "run-b");
    assertEquals(result.syncStartGeneration, 100);
    assertEquals(result.pageCursor, { inbox_items: "M" });
    assertEquals(result.patch.sync_start_generation, 100);
    assertEquals(result.shortCircuit, false);
  }
});

Deno.test("crash resume without start generation falls back to full pass", () => {
  const now = new Date("2026-09-08T12:00:00Z");
  const result = acquireLease({
    now,
    incomingRunId: null,
    currentGeneration: 101,
    newRunId: "run-b",
    row: emptyRow({
      page_cursor: { inbox_items: "M" },
      sync_start_generation: null,
    }),
  });
  assertEquals(result.kind, "acquired");
  if (result.kind === "acquired") {
    assertEquals(result.pageCursor, {});
    assertEquals(result.syncStartGeneration, 101);
  }
});

Deno.test("new full pass can short-circuit when generation is unchanged", () => {
  const now = new Date("2026-09-08T12:00:00Z");
  const result = acquireLease({
    now,
    incomingRunId: null,
    currentGeneration: 7,
    newRunId: "run-b",
    row: emptyRow({
      last_sync_status: "success",
      last_seen_generation: 7,
    }),
  });
  assertEquals(result.kind, "acquired");
  if (result.kind === "acquired") {
    assert(result.shortCircuit);
    assertEquals(result.syncStartGeneration, 7);
  }
});

Deno.test("pending settings status does not short-circuit", () => {
  const now = new Date("2026-09-08T12:00:00Z");
  const result = acquireLease({
    now,
    incomingRunId: null,
    currentGeneration: 7,
    newRunId: "run-b",
    row: emptyRow({
      last_sync_status: "pending",
      last_seen_generation: 7,
    }),
  });
  assertEquals(result.kind, "acquired");
  if (result.kind === "acquired") {
    assertEquals(result.shortCircuit, false);
  }
});

Deno.test("finishPass requires matching generations and no errors", () => {
  assertEquals(finishPass({ startGeneration: 10, endGeneration: 10, hasErrorLinks: false }).caughtUp, true);
  assertEquals(finishPass({ startGeneration: 10, endGeneration: 11, hasErrorLinks: false }).caughtUp, false);
  assertEquals(finishPass({ startGeneration: 10, endGeneration: 10, hasErrorLinks: true }).caughtUp, false);
  assertEquals(finishPass({ startGeneration: null, endGeneration: 10, hasErrorLinks: false }).caughtUp, false);
});

Deno.test("settings invalidation clears short-circuit fields", () => {
  const patch = settingsInvalidateShortCircuit();
  assertEquals(patch.last_seen_generation, null);
  assertEquals(patch.last_sync_status, "pending");
  assertEquals(patch.page_cursor, {});
  assertEquals(patch.sync_start_generation, null);
});
