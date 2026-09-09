import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleGoogleWebhook } from "./google_webhook.ts";
import type { ProviderWatch } from "./google_watch.ts";

const active: ProviderWatch = {
  id: "w1",
  connection_id: "conn-g",
  channel_id: "ch-1",
  resource_id: "res-1",
  channel_token: "tok-secret",
  sync_token: "sync-1",
  calendar_id: "cal-1",
  status: "active",
  expires_at: null,
};

function push(headers: Record<string, string>): Request {
  return new Request("https://example.test/google", {
    method: "POST",
    headers,
  });
}

Deno.test("exists enqueues incremental and does not list events", async () => {
  const accepted: string[] = [];
  const response = await handleGoogleWebhook(
    push({
      "X-Goog-Channel-ID": "ch-1",
      "X-Goog-Channel-Token": "tok-secret",
      "X-Goog-Resource-ID": "res-1",
      "X-Goog-Resource-State": "exists",
      "X-Goog-Message-Number": "10",
    }),
    {
      lookupWatch: async () => active,
      acceptWork: async (args) => {
        accepted.push(args.workType);
        return { accepted: true, duplicate: false };
      },
      recordSync: async () => {
        throw new Error("sync should not record exists");
      },
    },
  );
  assertEquals(response.status, 200);
  assertEquals(accepted, ["google_incremental"]);
});

Deno.test("sync is informational and does not enqueue list work", async () => {
  let syncs = 0;
  let work = 0;
  const creating: ProviderWatch = { ...active, status: "creating", resource_id: null };
  const response = await handleGoogleWebhook(
    push({
      "X-Goog-Channel-ID": "ch-1",
      "X-Goog-Channel-Token": "tok-secret",
      "X-Goog-Resource-ID": "res-early",
      "X-Goog-Resource-State": "sync",
      "X-Goog-Message-Number": "1",
    }),
    {
      lookupWatch: async () => creating,
      acceptWork: async () => {
        work += 1;
        return { accepted: true, duplicate: false };
      },
      recordSync: async () => {
        syncs += 1;
      },
    },
  );
  assertEquals(response.status, 200);
  assertEquals(syncs, 1);
  assertEquals(work, 0);
});

Deno.test("overlapping watches both authenticate; distinct message numbers both enqueue", async () => {
  const retiring: ProviderWatch = {
    ...active,
    id: "w-old",
    channel_id: "ch-old",
    channel_token: "tok-old",
    resource_id: "res-old",
    status: "retiring",
  };
  const creating: ProviderWatch = {
    ...active,
    id: "w-new",
    channel_id: "ch-new",
    channel_token: "tok-new",
    resource_id: null,
    status: "creating",
  };
  const accepted: string[] = [];
  const watches = new Map<string, ProviderWatch>([
    ["ch-old", retiring],
    ["ch-new", creating],
  ]);
  const handle = (channelId: string, token: string, resourceId: string, state: string, n: string) =>
    handleGoogleWebhook(
      push({
        "X-Goog-Channel-ID": channelId,
        "X-Goog-Channel-Token": token,
        "X-Goog-Resource-ID": resourceId,
        "X-Goog-Resource-State": state,
        "X-Goog-Message-Number": n,
      }),
      {
        lookupWatch: async (id) => watches.get(id) ?? null,
        acceptWork: async (args) => {
          accepted.push(`${args.eventKey}:${args.workType}`);
          return { accepted: true, duplicate: false };
        },
        recordSync: async (args) => {
          accepted.push(`${args.eventKey}:sync`);
        },
      },
    );
  const earlySync = await handle("ch-new", "tok-new", "res-early", "sync", "1");
  const oldExists = await handle("ch-old", "tok-old", "res-old", "exists", "10");
  const newExists = await handle("ch-new", "tok-new", "res-early", "exists", "2");
  assertEquals(earlySync.status, 200);
  assertEquals(oldExists.status, 200);
  assertEquals(newExists.status, 200);
  assertEquals(accepted, [
    "ch-new:1:sync",
    "ch-old:10:google_incremental",
    "ch-new:2:google_incremental",
  ]);
});

Deno.test("expired and unknown watches are ignored", async () => {
  const expired: ProviderWatch = { ...active, status: "expired" };
  const response = await handleGoogleWebhook(
    push({
      "X-Goog-Channel-ID": "ch-1",
      "X-Goog-Channel-Token": "tok-secret",
      "X-Goog-Resource-ID": "res-1",
      "X-Goog-Resource-State": "exists",
    }),
    {
      lookupWatch: async () => expired,
      acceptWork: async () => {
        throw new Error("expired must not enqueue");
      },
      recordSync: async () => {},
    },
  );
  assertEquals(response.status, 401);
});

Deno.test("unknown channel is 404 and bad token is 401", async () => {
  const unknown = await handleGoogleWebhook(
    push({
      "X-Goog-Channel-ID": "missing",
      "X-Goog-Channel-Token": "tok-secret",
      "X-Goog-Resource-State": "exists",
    }),
    {
      lookupWatch: async () => null,
      acceptWork: async () => ({ accepted: true, duplicate: false }),
      recordSync: async () => {},
    },
  );
  assertEquals(unknown.status, 404);
  const bad = await handleGoogleWebhook(
    push({
      "X-Goog-Channel-ID": "ch-1",
      "X-Goog-Channel-Token": "nope",
      "X-Goog-Resource-ID": "res-1",
      "X-Goog-Resource-State": "exists",
    }),
    {
      lookupWatch: async () => active,
      acceptWork: async () => ({ accepted: true, duplicate: false }),
      recordSync: async () => {},
    },
  );
  assertEquals(bad.status, 401);
});
