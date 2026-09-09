import { assertEquals } from "jsr:@std/assert@1";
import { decideOutbound, shouldSkipOutbound } from "./outbound_skip.ts";

Deno.test("skip conflict and error inbound states", () => {
  assertEquals(
    shouldSkipOutbound({
      entity_id: "a",
      external_id: "b",
      last_synced_revision: 1,
      sync_status: "synced",
      inbound_state: "conflict",
      content_hash: null,
    }, 2),
    true,
  );
  assertEquals(
    shouldSkipOutbound({
      entity_id: "a",
      external_id: "b",
      last_synced_revision: 1,
      sync_status: "error",
      inbound_state: "error",
      content_hash: null,
    }, 2),
    true,
  );
});

Deno.test("skip remote_deleted without exporting", () => {
  assertEquals(
    shouldSkipOutbound({
      entity_id: "a",
      external_id: "b",
      last_synced_revision: 2,
      sync_status: "synced",
      inbound_state: "remote_deleted",
      content_hash: null,
    }, 2),
    true,
  );
});

Deno.test("remote_deleted with a later local edit opens a conflict and does not export", () => {
  const decision = decideOutbound({
    entity_id: "a",
    external_id: "b",
    last_synced_revision: 2,
    sync_status: "synced",
    inbound_state: "remote_deleted",
    content_hash: null,
  }, 3);
  assertEquals(decision.skip, true);
  assertEquals(decision.openConflict, true);
  assertEquals(decision.reason, "remote_deleted_with_local_edit");
});

Deno.test("outbound hold after a failed inbound fetch blocks export", () => {
  assertEquals(
    decideOutbound({
      entity_id: "a",
      external_id: "b",
      last_synced_revision: 2,
      sync_status: "synced",
      inbound_state: "ready",
      outbound_hold: true,
      content_hash: null,
    }, 3).reason,
    "outbound_hold",
  );
  assertEquals(
    decideOutbound({
      entity_id: "a",
      external_id: "b",
      last_synced_revision: 2,
      sync_status: "synced",
      inbound_state: "ready",
      content_hash: null,
    }, 3, { connectionDeltaHold: true }).reason,
    "inbound_delta_hold",
  );
});

Deno.test("watch degradation without a delta hold does not freeze outbound", () => {
  assertEquals(
    decideOutbound({
      entity_id: "a",
      external_id: "b",
      last_synced_revision: 2,
      sync_status: "synced",
      inbound_state: "ready",
      content_hash: null,
    }, 3, { connectionDeltaHold: false }).skip,
    false,
  );
});

Deno.test("skip when last_synced matches revision", () => {
  assertEquals(
    shouldSkipOutbound({
      entity_id: "a",
      external_id: "b",
      last_synced_revision: 5,
      sync_status: "synced",
      inbound_state: "ready",
      content_hash: null,
    }, 5),
    true,
  );
  assertEquals(
    shouldSkipOutbound({
      entity_id: "a",
      external_id: "b",
      last_synced_revision: 5,
      sync_status: "synced",
      inbound_state: "ready",
      content_hash: null,
    }, 6),
    false,
  );
});
