import {
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  decideConflictResolution,
  freezeLocalSnapshot,
  isUuid,
  parseExpectedRevision,
  safeConflictPayload,
} from "./resolve_conflict.ts";

Deno.test("keep_local on live equal finishes without provider write", () => {
  const decision = decideConflictResolution({
    loadResult: "ready",
    choice: "keep_local",
    liveKind: "equal",
  });
  assertEquals(decision, { action: "finish_keep_local", acceptRemoteGone: false });
});

Deno.test("keep_local on drift pushes then finishes", () => {
  const decision = decideConflictResolution({
    loadResult: "ready",
    choice: "keep_local",
    liveKind: "drift",
  });
  assertEquals(decision, { action: "push_then_keep_local" });
});

Deno.test("keep_local on unsupported still pushes Diurna", () => {
  const decision = decideConflictResolution({
    loadResult: "ready",
    choice: "keep_local",
    liveKind: "unsupported_content",
  });
  assertEquals(decision, { action: "push_then_keep_local" });
});

Deno.test("keep_local on timed Google events may convert to all-day", () => {
  const decision = decideConflictResolution({
    loadResult: "ready",
    choice: "keep_local",
    liveKind: "unsupported_timed_event",
  });
  assertEquals(decision, { action: "push_then_keep_local" });
});

Deno.test("unsupported_recurrence is not resolvable by either side", () => {
  const keep = decideConflictResolution({
    loadResult: "ready",
    choice: "keep_local",
    liveKind: "unsupported_recurrence",
  });
  const useRemote = decideConflictResolution({
    loadResult: "ready",
    choice: "use_remote",
    liveKind: "unsupported_recurrence",
  });
  assertEquals(keep, { action: "error", code: "UNSUPPORTED_RECURRENCE" });
  assertEquals(useRemote, { action: "error", code: "UNSUPPORTED_RECURRENCE" });
  assertEquals(keep.action === "push_then_keep_local", false);
  assertEquals(useRemote.action === "apply_then_use_remote", false);
});

Deno.test("keep_local on remote_deleted accepts freeze without recreate", () => {
  const decision = decideConflictResolution({
    loadResult: "ready",
    choice: "keep_local",
    liveKind: "remote_deleted",
  });
  assertEquals(decision, { action: "finish_keep_local", acceptRemoteGone: true });
});

Deno.test("use_remote on drift applies once", () => {
  const decision = decideConflictResolution({
    loadResult: "ready",
    choice: "use_remote",
    liveKind: "drift",
  });
  assertEquals(decision, { action: "apply_then_use_remote" });
});

Deno.test("use_remote on equal does not mutate", () => {
  const decision = decideConflictResolution({
    loadResult: "ready",
    choice: "use_remote",
    liveKind: "equal",
  });
  assertEquals(decision, { action: "finish_use_remote_equal" });
});

Deno.test("use_remote refuses unsupported content", () => {
  const decision = decideConflictResolution({
    loadResult: "ready",
    choice: "use_remote",
    liveKind: "unsupported_content",
  });
  assertEquals(decision, { action: "error", code: "UNSUPPORTED_REMOTE" });
});

Deno.test("use_remote refuses timed Google events", () => {
  assertEquals(
    decideConflictResolution({
      loadResult: "ready",
      choice: "use_remote",
      liveKind: "unsupported_timed_event",
    }),
    { action: "error", code: "UNSUPPORTED_REMOTE" },
  );
});

Deno.test("use_remote on remote_deleted does not hard-delete local", () => {
  const decision = decideConflictResolution({
    loadResult: "ready",
    choice: "use_remote",
    liveKind: "remote_deleted",
  });
  assertEquals(decision, { action: "finish_use_remote_gone" });
});

Deno.test("stale local revision is a safe error", () => {
  const decision = decideConflictResolution({
    loadResult: "stale",
    choice: "keep_local",
    liveKind: "drift",
  });
  assertEquals(decision, { action: "error", code: "STALE_CONFLICT" });
});

Deno.test("already resolved is idempotent", () => {
  const decision = decideConflictResolution({
    loadResult: "already_resolved",
    choice: "keep_local",
    liveKind: "drift",
    alreadyStatus: "resolved_local",
  });
  assertEquals(decision, { action: "already_resolved", status: "resolved_local" });
});

Deno.test("fetch failure does not pick a side", () => {
  const decision = decideConflictResolution({
    loadResult: "ready",
    choice: "use_remote",
    liveKind: "fetch_failed",
  });
  assertEquals(decision, { action: "error", code: "PROVIDER_UNAVAILABLE" });
});

Deno.test("malformed expected revision is rejected", () => {
  assertEquals(parseExpectedRevision(2), 2);
  assertEquals(parseExpectedRevision(0), 0);
  assertEquals(parseExpectedRevision("3"), 3);
  assertEquals(parseExpectedRevision("0"), 0);
  assertEquals(parseExpectedRevision(Number.MAX_SAFE_INTEGER), Number.MAX_SAFE_INTEGER);
  assertEquals(parseExpectedRevision(String(Number.MAX_SAFE_INTEGER)), Number.MAX_SAFE_INTEGER);
  assertEquals(parseExpectedRevision(Number.MAX_SAFE_INTEGER + 1), null);
  assertEquals(parseExpectedRevision("9007199254740992"), null);
  assertEquals(parseExpectedRevision("90071992547409910"), null);
  assertEquals(parseExpectedRevision(1.5), null);
  assertEquals(parseExpectedRevision("01"), null);
  assertEquals(parseExpectedRevision("-1"), null);
  assertEquals(parseExpectedRevision("1.0"), null);
  assertEquals(parseExpectedRevision(""), null);
  assertEquals(parseExpectedRevision(null), null);
});

Deno.test("malformed UUIDs are rejected without requiring RFC version", () => {
  assertEquals(isUuid("23000000-0000-0000-0000-000000000190"), true);
  assertEquals(isUuid("not-a-uuid"), false);
  assertEquals(isUuid("23000000-0000-0000-0000-00000000019"), false);
});

Deno.test("frozen snapshot is a deep copy", () => {
  const source = { title: "Local", nested: { n: 1 } };
  const frozen = freezeLocalSnapshot(source);
  source.title = "mutated";
  source.nested.n = 9;
  assertEquals(frozen.title, "Local");
  assertEquals((frozen.nested as { n: number }).n, 1);
  assertEquals(Object.isFrozen(frozen), true);
});

Deno.test("safe payload omits snapshots and tokens", () => {
  const payload = safeConflictPayload({
    id: "c1",
    connection_id: "conn",
    provider: "notion",
    entity_type: "diary_entries",
    entity_id: "e1",
    status: "open",
    reason: "bootstrap_remote_drift",
    local_revision: 1,
    last_synced_revision: 1,
    created_at: "2026-09-09T00:00:00Z",
    entity_label: "2026-07-31",
    field_categories: ["title", "content"],
    can_keep_local_push: true,
    can_use_remote: true,
    blocked_reason: null,
    local_snapshot: { content: "secret diary" },
    remote_snapshot: { patch: { title: "nope" } },
    channel_token: "secret",
  });
  assertEquals("local_snapshot" in payload, false);
  assertEquals("remote_snapshot" in payload, false);
  assertEquals("channel_token" in payload, false);
  assertEquals(payload.entity_label, "2026-07-31");
  assertEquals(payload.field_categories, ["title", "content"]);
});
