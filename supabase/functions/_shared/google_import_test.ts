import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { importGoogleEvent, noteFromGoogleDescription } from "./google_import.ts";

Deno.test("all-day event maps summary date and note", () => {
  const result = importGoogleEvent({
    id: "evt-1",
    etag: "\"etag-1\"",
    updated: "2026-09-09T12:00:00.000Z",
    summary: "Dentist",
    description: "Bring xrays\nCompleted in Diurna",
    start: { date: "2026-09-11" },
    end: { date: "2026-09-12" },
  });
  assertEquals(result.kind, "update");
  if (result.kind === "update") {
    assertEquals(result.patch.title, "Dentist");
    assertEquals(result.patch.event_date, "2026-09-11");
    assertEquals(result.patch.note, "Bring xrays");
    assertEquals("is_completed" in result.patch, false);
    assertEquals("remind_at" in result.patch, false);
  }
});

Deno.test("timed events are unsupported and not coerced to a date", () => {
  const result = importGoogleEvent({
    id: "evt-2",
    etag: "\"e2\"",
    summary: "Call",
    start: { dateTime: "2026-09-11T15:00:00+08:00" },
  });
  assertEquals(result.kind, "unsupported_timed_event");
});

Deno.test("recurring events are unsupported", () => {
  assertEquals(
    importGoogleEvent({
      id: "evt-3",
      start: { date: "2026-09-11" },
      recurrence: ["RRULE:FREQ=WEEKLY"],
    }).kind,
    "unsupported_recurrence",
  );
  assertEquals(
    importGoogleEvent({
      id: "evt-4",
      start: { date: "2026-09-11" },
      recurringEventId: "master",
    }).kind,
    "unsupported_recurrence",
  );
});

Deno.test("cancelled events are remote_deleted", () => {
  assertEquals(
    importGoogleEvent({ id: "evt-5", status: "cancelled", start: { date: "2026-09-11" } }).kind,
    "remote_deleted",
  );
  assertEquals(
    importGoogleEvent({ id: "evt-6", deleted: true }).kind,
    "remote_deleted",
  );
});

Deno.test("Completed in Diurna footer is not parsed as completion state", () => {
  assertEquals(noteFromGoogleDescription("Completed in Diurna"), "");
  assertEquals(noteFromGoogleDescription("note\nCompleted in Diurna"), "note");
  assertEquals(noteFromGoogleDescription(undefined), undefined);
});
