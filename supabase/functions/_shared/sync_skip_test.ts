import { assertEquals } from "jsr:@std/assert@1";
import { shouldSkipOutbound } from "./outbound_skip.ts";

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
