import { assertEquals } from "jsr:@std/assert@1";
import { decideProviderVersion, decideRevision } from "./conflicts.ts";

Deno.test("google etag equality is duplicate", () => {
  assertEquals(
    decideProviderVersion({
      provider: "google",
      etag: "a",
      storedEtag: "a",
      mappedEqual: false,
    }),
    "duplicate",
  );
});

Deno.test("notion equal timestamp with different mapped continues", () => {
  const t = new Date("2026-09-09T12:00:00Z");
  assertEquals(
    decideProviderVersion({
      provider: "notion",
      incomingUpdated: t,
      storedUpdated: t,
      mappedEqual: false,
    }),
    "continue",
  );
});

Deno.test("notion equal timestamp with equal mapped is duplicate", () => {
  const t = new Date("2026-09-09T12:00:00Z");
  assertEquals(
    decideProviderVersion({
      provider: "notion",
      incomingUpdated: t,
      storedUpdated: t,
      mappedEqual: true,
    }),
    "duplicate",
  );
});

Deno.test("older updated is stale", () => {
  assertEquals(
    decideProviderVersion({
      provider: "notion",
      incomingUpdated: new Date("2026-09-09T11:00:00Z"),
      storedUpdated: new Date("2026-09-09T12:00:00Z"),
      mappedEqual: false,
    }),
    "stale",
  );
});

Deno.test("remote_deleted with local edit is conflict", () => {
  assertEquals(
    decideRevision({
      revision: 3,
      lastSyncedRevision: 2,
      inboundState: "remote_deleted",
      operation: "update",
      mappedEqual: false,
    }),
    "conflict",
  );
});

Deno.test("safe apply when revision matches and mapped differs", () => {
  assertEquals(
    decideRevision({
      revision: 5,
      lastSyncedRevision: 5,
      inboundState: "ready",
      operation: "update",
      mappedEqual: false,
    }),
    "applied",
  );
});
