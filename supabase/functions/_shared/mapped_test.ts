import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  nextInboundStatus,
  patchMatchesRow,
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
});

Deno.test("inbound status transitions", () => {
  assertEquals(nextInboundStatus("disabled", "bootstrap_start"), "bootstrapping");
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
