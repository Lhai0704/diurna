import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { decryptTokenBundle, encryptTokenBundle } from "./crypto.ts";
import { googleEventId } from "./google_id.ts";

Deno.test("token bundle round-trip", async () => {
  const secret = "integration-token-key-for-tests";
  const encrypted = await encryptTokenBundle(
    { access_token: "at-1", refresh_token: "rt-1" },
    secret,
  );
  assertEquals(encrypted.nonce.length, 12);
  const decrypted = await decryptTokenBundle(encrypted, secret);
  assertEquals(decrypted.access_token, "at-1");
  assertEquals(decrypted.refresh_token, "rt-1");
});

Deno.test("each encryption uses a unique nonce", async () => {
  const secret = "integration-token-key-for-tests";
  const a = await encryptTokenBundle(
    { access_token: "at", refresh_token: "rt" },
    secret,
  );
  const b = await encryptTokenBundle(
    { access_token: "at", refresh_token: "rt-2" },
    secret,
  );
  assert(a.cipher !== b.cipher);
  assertEquals(a.nonce.length, 12);
  assert(Array.from(a.nonce).join(",") !== Array.from(b.nonce).join(","));
});

Deno.test("google event id is base32hex-safe", () => {
  const id = googleEventId("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee");
  assertEquals(id, "durnaaaaaaaaabbbb4ccc8dddeeeeeeeeeeee");
  assert(/^[0-9a-v]+$/.test(id));
  assert(id.length >= 5 && id.length <= 1024);
});
