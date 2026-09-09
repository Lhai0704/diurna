import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { googleEventBody, nextDate } from "./google_export.ts";
import { googleEventId } from "./google_id.ts";

Deno.test("outbound google event stays all-day with completion footer", () => {
  const id = googleEventId("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee");
  const body = googleEventBody({
    id: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
    title: "Dentist",
    event_date: "2026-09-11",
    note: "Bring xrays",
    is_completed: true,
    revision: 3,
  }, id);
  assertEquals(body.start, { date: "2026-09-11" });
  assertEquals(body.end, { date: nextDate("2026-09-11") });
  assertEquals(body.description, "Bring xrays\nCompleted in Diurna");
  assertEquals(body.extendedProperties.private.diurnaCompleted, "true");
  assertEquals(body.extendedProperties.private.diurnaRevision, "3");
});

Deno.test("nextDate is exclusive all-day end", () => {
  assertEquals(nextDate("2026-09-11"), "2026-09-12");
});
