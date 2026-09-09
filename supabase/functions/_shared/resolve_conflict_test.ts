import {
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  decideConflictResolution,
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

Deno.test("use_remote refuses timed and recurring Google events", () => {
  assertEquals(
    decideConflictResolution({
      loadResult: "ready",
      choice: "use_remote",
      liveKind: "unsupported_timed_event",
    }),
    { action: "error", code: "UNSUPPORTED_REMOTE" },
  );
  assertEquals(
    decideConflictResolution({
      loadResult: "ready",
      choice: "use_remote",
      liveKind: "unsupported_recurrence",
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
