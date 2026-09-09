import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { decideGoogleBootstrapLink } from "./google_bootstrap.ts";

const row = {
  title: "Dentist",
  event_date: "2026-09-11",
  note: "n",
  is_completed: true,
  remind_at: "2026-09-11T08:00:00Z",
};

Deno.test("Google bootstrap equal mapped state is ready without using Diurna-only fields", () => {
  const decision = decideGoogleBootstrapLink({
    row,
    remote: {
      id: "gcal-dentist",
      etag: "\"e1\"",
      updated: "2026-09-09T12:00:00.000Z",
      summary: "Dentist",
      description: "n",
      start: { date: "2026-09-11" },
    },
  });
  assertEquals(decision.action, "ready");
});

Deno.test("Google bootstrap equal calendar date is ready when local event_date is a Date", () => {
  const decision = decideGoogleBootstrapLink({
    row: {
      ...row,
      event_date: new Date("2026-09-11T00:00:00.000Z"),
    },
    remote: {
      id: "gcal-dentist",
      summary: "Dentist",
      description: "n",
      start: { date: "2026-09-11" },
    },
  });
  assertEquals(decision.action, "ready");
});

Deno.test("Google bootstrap remote drift is conflicted, not overwritten", () => {
  const decision = decideGoogleBootstrapLink({
    row,
    remote: {
      id: "gcal-dentist",
      summary: "Remote title",
      description: "n",
      start: { date: "2026-09-11" },
    },
  });
  assertEquals(decision.action, "drift");
});

Deno.test("Google bootstrap timed and recurring events are explicit conflicts", () => {
  assertEquals(
    decideGoogleBootstrapLink({
      row,
      remote: { id: "t", start: { dateTime: "2026-09-11T15:00:00Z" } },
    }).action,
    "unsupported",
  );
  assertEquals(
    decideGoogleBootstrapLink({
      row,
      remote: { id: "r", start: { date: "2026-09-11" }, recurrence: ["RRULE:FREQ=WEEKLY"] },
    }).action,
    "unsupported",
  );
});

Deno.test("Google bootstrap missing or cancelled remote is remote_deleted", () => {
  assertEquals(
    decideGoogleBootstrapLink({ row, remote: undefined }).action,
    "remote_deleted",
  );
  const cancelled = decideGoogleBootstrapLink({
    row,
    remote: { id: "gcal-dentist", status: "cancelled", start: { date: "2026-09-11" } },
  });
  assertEquals(cancelled.action, "remote_deleted");
  if (cancelled.action === "remote_deleted") {
    assertEquals(cancelled.missing, false);
  }
});
