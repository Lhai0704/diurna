import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  hmacSha256Hex,
  parseNotionVerificationHandshake,
  timingSafeEqual,
  verifyNotionSignature,
} from "./webhook_auth.ts";

Deno.test("handshake extracts verification_token only", () => {
  assertEquals(
    parseNotionVerificationHandshake(
      '{"verification_token":"secret_abc"}',
    ),
    "secret_abc",
  );
  assertEquals(
    parseNotionVerificationHandshake('{"id":"evt","type":"page.created"}'),
    null,
  );
  assertEquals(parseNotionVerificationHandshake("not-json"), null);
});

Deno.test("notion HMAC uses raw body", async () => {
  const token = "diurna_test_verification_token";
  const body = '{"id":"evt-1","type":"page.properties_updated"}';
  const hex = await hmacSha256Hex(token, body);
  assert(
    await verifyNotionSignature({
      rawBody: body,
      signatureHeader: `sha256=${hex}`,
      verificationToken: token,
    }),
  );
  assertEquals(
    await verifyNotionSignature({
      rawBody: body,
      signatureHeader: `sha256=${hex}`,
      verificationToken: "wrong",
    }),
    false,
  );
  assertEquals(
    await verifyNotionSignature({
      rawBody: '{"id":"evt-1"}',
      signatureHeader: `sha256=${hex}`,
      verificationToken: token,
    }),
    false,
  );
});

Deno.test("timingSafeEqual rejects different lengths", () => {
  assertEquals(timingSafeEqual("abc", "ab"), false);
  assert(timingSafeEqual("same", "same"));
});
