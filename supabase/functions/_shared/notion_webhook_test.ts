import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { hmacSha256Hex } from "./webhook_auth.ts";
import { handleNotionWebhook } from "./notion_webhook.ts";

const token = "secret_test_verification_token";

async function signedRequest(body: string): Promise<Request> {
  const hex = await hmacSha256Hex(token, body);
  return new Request("https://example.test/notion", {
    method: "POST",
    headers: { "X-Notion-Signature": `sha256=${hex}` },
    body,
  });
}

Deno.test("handshake stores token and does not call fetch", async () => {
  const stored: string[] = [];
  const response = await handleNotionWebhook(
    new Request("https://example.test/notion", {
      method: "POST",
      body: '{"verification_token":"secret_from_notion"}',
    }),
    {
      loadVerificationToken: async () => token,
      storeVerificationToken: async (value) => {
        stored.push(value);
      },
      lookupConnectionIds: async () => [],
      acceptEvent: async () => {
        throw new Error("should not enqueue handshake");
      },
    },
  );
  assertEquals(response.status, 200);
  assertEquals(await response.text(), "");
  assertEquals(stored, ["secret_from_notion"]);
});

Deno.test("signed page event enqueues and never fetches Notion", async () => {
  const accepted: Array<{ eventKey: string; pageId: string }> = [];
  const body = JSON.stringify({
    id: "evt-1",
    type: "page.properties_updated",
    workspace_id: "ws-1",
    entity: { id: "page-1", type: "page" },
  });
  const response = await handleNotionWebhook(await signedRequest(body), {
    loadVerificationToken: async () => token,
    storeVerificationToken: async () => {
      throw new Error("should not store");
    },
    lookupConnectionIds: async () => ["conn-1"],
    acceptEvent: async (args) => {
      accepted.push(args);
      return { accepted: true, duplicate: false };
    },
  });
  assertEquals(response.status, 200);
  assertEquals(accepted.length, 1);
  assertEquals(accepted[0].eventKey, "evt-1:conn-1");
  assertEquals(accepted[0].pageId, "page-1");
});

Deno.test("invalid signature is 401", async () => {
  const response = await handleNotionWebhook(
    new Request("https://example.test/notion", {
      method: "POST",
      headers: { "X-Notion-Signature": "sha256=deadbeef" },
      body: '{"id":"evt-1","type":"page.properties_updated","entity":{"id":"p"}}',
    }),
    {
      loadVerificationToken: async () => token,
      storeVerificationToken: async () => {},
      lookupConnectionIds: async () => ["conn-1"],
      acceptEvent: async () => {
        throw new Error("must not enqueue");
      },
    },
  );
  assertEquals(response.status, 401);
});

Deno.test("unknown event type is ignored without enqueue", async () => {
  let enqueued = 0;
  const body = JSON.stringify({
    id: "evt-2",
    type: "comment.created",
    entity: { id: "page-1" },
  });
  const response = await handleNotionWebhook(await signedRequest(body), {
    loadVerificationToken: async () => token,
    storeVerificationToken: async () => {},
    lookupConnectionIds: async () => ["conn-1"],
    acceptEvent: async () => {
      enqueued += 1;
      return { accepted: true, duplicate: false };
    },
  });
  assertEquals(response.status, 200);
  assertEquals(enqueued, 0);
  const payload = await response.json() as { ignored?: boolean };
  assert(payload.ignored);
});
