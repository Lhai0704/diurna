import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FakeAdvisoryBackend, runWithLock } from "./inbound_lock.ts";

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
