import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { decideNotionLatestFetch } from "./notion_worker.ts";

Deno.test("stale page.deleted after undelete fetches live page and restores", () => {
  assertEquals(
    decideNotionLatestFetch({
      status: 200,
      page: { archived: false, in_trash: false },
      inboundState: "remote_deleted",
    }),
    "restore_then_import",
  );
});

Deno.test("missing or archived page is remote_deleted", () => {
  assertEquals(
    decideNotionLatestFetch({
      status: 404,
      page: null,
      inboundState: "ready",
    }),
    "remote_deleted",
  );
  assertEquals(
    decideNotionLatestFetch({
      status: 200,
      page: { archived: true },
      inboundState: "ready",
    }),
    "remote_deleted",
  );
});

Deno.test("provider fetch failure is not treated as delete", () => {
  assertEquals(
    decideNotionLatestFetch({
      status: 503,
      page: null,
      inboundState: "ready",
    }),
    "fetch_failed",
  );
});
