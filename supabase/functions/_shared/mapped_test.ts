import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  nextInboundStatus,
  patchMatchesRow,
  shouldEnqueueBootstrap,
  shouldEnqueueRepair,
  shouldRenewWatch,
} from "./mapped.ts";

Deno.test("patchMatchesRow ignores unspecified Diurna-only fields", () => {
  assertEquals(
    patchMatchesRow(
      { title: "A", event_date: "2026-09-11", note: "n", is_completed: true, remind_at: "x" },
      { title: "A", event_date: "2026-09-11", note: "n" },
    ),
    true,
  );
  assertEquals(
    patchMatchesRow(
      { title: "A", event_date: "2026-09-11", note: "n" },
      { title: "B", event_date: "2026-09-11", note: "n" },
    ),
    false,
  );
});

Deno.test("patchMatchesRow compares date-only fields as calendar dates", () => {
  assertEquals(
    patchMatchesRow(
      { entry_date: new Date("2026-09-09T00:00:00.000Z"), title: "Day" },
      { entry_date: "2026-09-09", title: "Day" },
    ),
    true,
  );
  assertEquals(
    patchMatchesRow(
      { event_date: "2026-09-09T15:04:05.000Z", title: "Task" },
      { event_date: "2026-09-09", title: "Task" },
    ),
    true,
  );
  assertEquals(
    patchMatchesRow(
      { entry_date: "2026-09-08" },
      { entry_date: "2026-09-09" },
    ),
    false,
  );
  assertEquals(
    patchMatchesRow(
      { title: "2026-09-09T15:04:05.000Z" },
      { title: "2026-09-09" },
    ),
    false,
  );
  assertEquals(
    patchMatchesRow(
      { mood: null, is_completed: true, title: "A" },
      { mood: null, is_completed: true, title: "A" },
    ),
    true,
  );
});

Deno.test("shouldRenewWatch uses safety window and skips creating", () => {
  const now = new Date("2026-09-09T12:00:00Z");
  assertEquals(
    shouldRenewWatch({
      now,
      expiresAt: "2026-09-10T12:00:00Z",
      status: "active",
      hasCreating: false,
    }),
    true,
  );
  assertEquals(
    shouldRenewWatch({
      now,
      expiresAt: "2026-10-01T12:00:00Z",
      status: "active",
      hasCreating: false,
    }),
    false,
  );
  assertEquals(
    shouldRenewWatch({
      now,
      expiresAt: "2026-09-10T12:00:00Z",
      status: "active",
      hasCreating: true,
    }),
    false,
  );
  assertEquals(
    shouldRenewWatch({
      now,
      expiresAt: null,
      status: "active",
      hasCreating: false,
    }),
    false,
  );
});

Deno.test("repair cadence is 15 minutes and only when active/degraded", () => {
  const now = new Date("2026-09-09T12:00:00Z");
  assertEquals(
    shouldEnqueueRepair({
      now,
      lastInboundAt: "2026-09-09T11:40:00Z",
      inboundStatus: "active",
    }),
    true,
  );
  assertEquals(
    shouldEnqueueRepair({
      now,
      lastInboundAt: "2026-09-09T11:50:00Z",
      inboundStatus: "active",
    }),
    false,
  );
  assertEquals(
    shouldEnqueueRepair({
      now,
      lastInboundAt: "2026-09-09T11:00:00Z",
      inboundStatus: "bootstrapping",
    }),
    false,
  );
  assertEquals(
    shouldEnqueueRepair({
      now,
      lastInboundAt: "2026-09-09T11:50:00Z",
      inboundStatus: "active",
      hasRepairState: true,
    }),
    true,
  );
});

Deno.test("maintenance never auto-bootstraps disabled connections", () => {
  assertEquals(
    shouldEnqueueBootstrap({ inboundStatus: "disabled", hasInflightBootstrap: false }),
    false,
  );
  assertEquals(
    shouldEnqueueBootstrap({ inboundStatus: "bootstrapping", hasInflightBootstrap: false }),
    true,
  );
  assertEquals(
    shouldEnqueueBootstrap({ inboundStatus: "bootstrapping", hasInflightBootstrap: true }),
    false,
  );
  assertEquals(
    shouldEnqueueBootstrap({ inboundStatus: "active", hasInflightBootstrap: false }),
    false,
  );
});

Deno.test("inbound status transitions", () => {
  assertEquals(nextInboundStatus("disabled", "bootstrap_start"), "disabled");
  assertEquals(nextInboundStatus("disabled", "bootstrap_ok_watch_ok"), "disabled");
  assertEquals(nextInboundStatus("disabled", "watch_ok"), "disabled");
  assertEquals(nextInboundStatus("error", "bootstrap_start"), "error");
  assertEquals(nextInboundStatus("bootstrapping", "bootstrap_start"), "bootstrapping");
  assertEquals(nextInboundStatus("bootstrapping", "bootstrap_ok_watch_ok"), "active");
  assertEquals(nextInboundStatus("bootstrapping", "bootstrap_ok_watch_failed"), "degraded");
  assertEquals(nextInboundStatus("active", "watch_failed"), "degraded");
  assertEquals(nextInboundStatus("degraded", "watch_ok"), "active");
  assertEquals(nextInboundStatus("active", "reauth"), "error");
  assertEquals(nextInboundStatus("error", "watch_ok"), "error");
  assertEquals(nextInboundStatus("active", "disconnect"), "disabled");
  assertEquals(nextInboundStatus("active", "calendar_gone"), "error");
  assertEquals(nextInboundStatus("active", "transient_fail"), "degraded");
  assertEquals(nextInboundStatus("degraded", "transient_ok"), "active");
  assertEquals(nextInboundStatus("bootstrapping", "bootstrap_ok_watch_ok"), "active");
});
