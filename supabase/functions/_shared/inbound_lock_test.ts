import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  FakeAdvisoryBackend,
  FakeProcessingLease,
  runWithLock,
} from "./inbound_lock.ts";
import { startInboundWorkHeartbeat } from "./inbound_work.ts";

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

Deno.test("shared session lock reenters and overlaps critical sections", async () => {
  const backend = new FakeAdvisoryBackend();
  const shared = backend.newSession();
  const events: string[] = [];
  await Promise.all([
    runWithLock(shared, "conn", async () => {
      events.push("a-enter");
      await wait(20);
      events.push("a-exit");
    }),
    runWithLock(shared, "conn", async () => {
      events.push("b-enter");
      await wait(5);
      events.push("b-exit");
    }),
  ]);
  assertEquals(events.includes("b-enter") && events.indexOf("b-enter") < events.indexOf("a-exit"), true);
});

Deno.test("dedicated sessions keep provider/apply critical sections exclusive", async () => {
  const backend = new FakeAdvisoryBackend();
  const workerA = backend.newSession();
  const workerB = backend.newSession();
  const events: string[] = [];
  await Promise.all([
    runWithLock(workerA, "conn", async () => {
      events.push("bootstrap-enter");
      await wait(20);
      events.push("bootstrap-exit");
    }),
    runWithLock(workerB, "conn", async () => {
      events.push("incremental-enter");
      events.push("incremental-exit");
    }),
  ]);
  const bootstrapExit = events.indexOf("bootstrap-exit");
  const incrementalEnter = events.indexOf("incremental-enter");
  const bootstrapEnter = events.indexOf("bootstrap-enter");
  if (bootstrapEnter === 0) {
    assertEquals(incrementalEnter > bootstrapExit, true);
  } else {
    assertEquals(events.indexOf("incremental-exit") < bootstrapEnter, true);
  }
});

Deno.test("heartbeat keeps a waiting worker from being reclaimed after the original lease", async () => {
  const ttl = 3;
  const held = new FakeProcessingLease(0, ttl);
  const waiting = new FakeProcessingLease(0, ttl);
  const backend = new FakeAdvisoryBackend();
  const sessionA = backend.newSession();
  const sessionB = backend.newSession();

  const run = runWithLock(sessionA, "conn", async () => {
    held.heartbeat(1, ttl);
    waiting.heartbeat(1, ttl);
    await wait(20);
    held.heartbeat(4, ttl);
    waiting.heartbeat(4, ttl);
    assertEquals(waiting.reclaim(4), false);
    assertEquals(waiting.status, "processing");
    assertEquals(held.reclaim(4), false);
  });
  const waiter = runWithLock(sessionB, "conn", async () => {
    waiting.heartbeat(5, ttl);
  });
  await Promise.all([run, waiter]);
  assertEquals(waiting.status, "processing");
});

Deno.test("startInboundWorkHeartbeat extends a live lease until stopped", async () => {
  let ticks = 0;
  const handle = startInboundWorkHeartbeat("work-b", {
    intervalMs: 15,
    heartbeat: async () => {
      ticks += 1;
      return { result: "ok" };
    },
  });
  await wait(40);
  handle.stop();
  assertEquals(ticks >= 2, true);
  assertEquals(handle.lost(), false);
});

Deno.test("reclaim still recovers a worker that stopped heartbeating", () => {
  const dead = new FakeProcessingLease(0, 3);
  assertEquals(dead.reclaim(4), true);
  assertEquals(dead.status, "pending");
  assertEquals(dead.heartbeat(5, 3), "ignored");
});
