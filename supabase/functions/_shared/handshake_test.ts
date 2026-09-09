import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handshakeDecision, hashHandshakeNonce } from "./handshake.ts";

const future = new Date("2026-09-09T13:00:00Z");
const now = new Date("2026-09-09T12:00:00Z");

Deno.test("attacker handshake before activation is rejected", () => {
  assertEquals(
    handshakeDecision({ hasActiveToken: false, arm: null, now }),
    "reject",
  );
});

Deno.test("second unsolicited handshake cannot replace an active token", () => {
  assertEquals(
    handshakeDecision({
      hasActiveToken: true,
      arm: {
        purpose: "initial",
        nonceHash: "abc",
        expiresAt: future,
        consumedAt: null,
      },
      now,
    }),
    "reject",
  );
  assertEquals(
    handshakeDecision({ hasActiveToken: true, arm: null, now }),
    "reject",
  );
});

Deno.test("authorized rotation succeeds", () => {
  assertEquals(
    handshakeDecision({
      hasActiveToken: true,
      arm: {
        purpose: "rotate",
        nonceHash: "abc",
        expiresAt: future,
        consumedAt: null,
      },
      now,
    }),
    "store",
  );
});

Deno.test("initial armed handshake is accepted only once", () => {
  assertEquals(
    handshakeDecision({
      hasActiveToken: false,
      arm: {
        purpose: "initial",
        nonceHash: "abc",
        expiresAt: future,
        consumedAt: null,
      },
      now,
    }),
    "store",
  );
  assertEquals(
    handshakeDecision({
      hasActiveToken: false,
      arm: {
        purpose: "initial",
        nonceHash: "abc",
        expiresAt: future,
        consumedAt: now,
      },
      now,
    }),
    "reject",
  );
});

Deno.test("handshake nonce hash is not the nonce", async () => {
  const hash = await hashHandshakeNonce("diurna_test_setup_nonce");
  assertEquals(hash.length, 64);
  assertEquals(hash.includes("diurna_test_setup_nonce"), false);
});
