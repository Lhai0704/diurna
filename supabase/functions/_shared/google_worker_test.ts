import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { listGoogleEvents } from "./google_worker.ts";

Deno.test("paginated list returns nextSyncToken only after the last page", async () => {
  const urls: string[] = [];
  const listed = await listGoogleEvents({
    calendarId: "cal-1",
    syncToken: "sync-old",
    fetch: async (url) => {
      urls.push(url);
      if (url.includes("pageToken=page-2")) {
        return new Response(
          JSON.stringify({
            items: [{ id: "b", start: { date: "2026-09-12" } }],
            nextSyncToken: "sync-new",
          }),
          { status: 200 },
        );
      }
      return new Response(
        JSON.stringify({
          items: [{ id: "a", start: { date: "2026-09-11" } }],
          nextPageToken: "page-2",
        }),
        { status: 200 },
      );
    },
  });
  assertEquals(listed.items.map((item) => item.id), ["a", "b"]);
  assertEquals(listed.nextSyncToken, "sync-new");
  assertEquals(listed.fullResync, false);
  assert(urls[0].includes("syncToken=sync-old"));
  assert(urls[1].includes("pageToken=page-2"));
  assert(urls[1].includes("syncToken=sync-old"));
});

Deno.test("410 Gone restarts a full list and does not keep incremental items", async () => {
  let calls = 0;
  const listed = await listGoogleEvents({
    calendarId: "cal-1",
    syncToken: "stale",
    fetch: async (url) => {
      calls += 1;
      if (url.includes("syncToken=stale")) {
        return new Response("gone", { status: 410 });
      }
      assertEquals(url.includes("syncToken="), false);
      return new Response(
        JSON.stringify({
          items: [{ id: "kept", etag: "\"e1\"", start: { date: "2026-09-11" } }],
          nextSyncToken: "sync-fresh",
        }),
        { status: 200 },
      );
    },
  });
  assertEquals(calls, 2);
  assertEquals(listed.fullResync, true);
  assertEquals(listed.items.length, 1);
  assertEquals(listed.items[0].id, "kept");
  assertEquals(listed.nextSyncToken, "sync-fresh");
});
