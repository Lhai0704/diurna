import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { shouldRenewWatch } from "./mapped.ts";
import {
  authenticateGoogleNotification,
  createGoogleWatch,
  decideWatchRenewal,
  generateWatchSecrets,
  pickSyncTokenSource,
  renewGoogleWatch,
  type ProviderWatch,
  type WatchPersistence,
} from "./google_watch.ts";

const watch = (overrides: Partial<ProviderWatch> = {}): ProviderWatch => ({
  id: "w1",
  connection_id: "c1",
  channel_id: "ch-1",
  resource_id: "res-1",
  channel_token: "tok-secret",
  sync_token: null,
  calendar_id: "cal-1",
  status: "active",
  expires_at: null,
  ...overrides,
});

Deno.test("creating watch authenticates early sync without resource_id", () => {
  assertEquals(
    authenticateGoogleNotification({
      channelId: "ch-1",
      channelToken: "tok-secret",
      resourceId: "res-arriving-early",
      watch: watch({ status: "creating", resource_id: null }),
    }),
    "ok",
  );
});

Deno.test("sync is not required to treat a watch as authenticatable", () => {
  assertEquals(
    authenticateGoogleNotification({
      channelId: "ch-1",
      channelToken: "tok-secret",
      resourceId: "res-1",
      watch: watch({ status: "active" }),
    }),
    "ok",
  );
});

Deno.test("unknown channel and token mismatch", () => {
  assertEquals(
    authenticateGoogleNotification({
      channelId: "ch-1",
      channelToken: "tok-secret",
      resourceId: "res-1",
      watch: null,
    }),
    "unknown",
  );
  assertEquals(
    authenticateGoogleNotification({
      channelId: "ch-1",
      channelToken: "wrong",
      resourceId: "res-1",
      watch: watch(),
    }),
    "unauthorized",
  );
});

Deno.test("active watch requires X-Goog-Resource-ID to match", () => {
  assertEquals(
    authenticateGoogleNotification({
      channelId: "ch-1",
      channelToken: "tok-secret",
      resourceId: null,
      watch: watch({ resource_id: "res-1", status: "active" }),
    }),
    "mismatch",
  );
});

Deno.test("stored resource_id mismatch is rejected", () => {
  assertEquals(
    authenticateGoogleNotification({
      channelId: "ch-1",
      channelToken: "tok-secret",
      resourceId: "other",
      watch: watch({ resource_id: "res-1", status: "active" }),
    }),
    "mismatch",
  );
});

Deno.test("expired watches are unauthorized", () => {
  assertEquals(
    authenticateGoogleNotification({
      channelId: "ch-1",
      channelToken: "tok-secret",
      resourceId: "res-1",
      watch: watch({ status: "expired" }),
    }),
    "unauthorized",
  );
});

Deno.test("retiring and creating watches remain authenticatable during overlap", () => {
  assertEquals(
    authenticateGoogleNotification({
      channelId: "ch-1",
      channelToken: "tok-secret",
      resourceId: "res-1",
      watch: watch({ status: "retiring" }),
    }),
    "ok",
  );
  assertEquals(
    authenticateGoogleNotification({
      channelId: "ch-new",
      channelToken: "tok-new",
      resourceId: "res-early",
      watch: watch({
        channel_id: "ch-new",
        channel_token: "tok-new",
        status: "creating",
        resource_id: null,
      }),
    }),
    "ok",
  );
});

Deno.test("renewal is not due every worker tick", () => {
  const now = new Date("2026-09-09T12:00:00Z");
  assertEquals(
    shouldRenewWatch({
      now,
      expiresAt: "2026-09-16T12:00:00Z",
      status: "active",
      hasCreating: false,
    }),
    false,
  );
});

Deno.test("channel token is unpredictable", () => {
  const a = generateWatchSecrets();
  const b = generateWatchSecrets();
  assertEquals(a.channelToken.length, 64);
  assert(a.channelToken !== b.channelToken);
  assert(a.channelId !== b.channelId);
});

Deno.test("renewal decision is idempotent while creating or not due", () => {
  const now = new Date("2026-09-09T12:00:00Z");
  assertEquals(
    decideWatchRenewal({
      now,
      watches: [
        {
          status: "active",
          expires_at: "2026-09-10T12:00:00Z",
          channel_id: "old",
          calendar_id: "cal",
        },
        {
          status: "creating",
          expires_at: null,
          channel_id: "new",
          calendar_id: "cal",
        },
      ],
    }),
    { action: "skip", reason: "creating" },
  );
  assertEquals(
    decideWatchRenewal({
      now,
      watches: [{
        status: "active",
        expires_at: "2026-09-16T12:00:00Z",
        channel_id: "new",
        calendar_id: "cal",
      }],
    }),
    { action: "skip", reason: "not_due" },
  );
  assertEquals(
    decideWatchRenewal({
      now,
      watches: [{
        status: "active",
        expires_at: "2026-09-10T12:00:00Z",
        channel_id: "old",
        calendar_id: "cal",
      }],
    }),
    { action: "renew", oldChannelId: "old", calendarId: "cal" },
  );
});

function memoryWatches(seed: ProviderWatch[] = []) {
  const rows = seed.map((item) => ({ ...item }));
  const calls: string[] = [];
  const store: Partial<WatchPersistence> = {
    persistCreating: async (args) => {
      calls.push("persist_creating");
      const watch: ProviderWatch = {
        id: `id-${args.channelId}`,
        connection_id: args.connectionId,
        channel_id: args.channelId,
        channel_token: args.channelToken,
        calendar_id: args.calendarId,
        resource_id: null,
        sync_token: null,
        status: "creating",
        expires_at: null,
      };
      rows.push(watch);
      return watch;
    },
    activate: async (args) => {
      calls.push("activate");
      const row = rows.find((item) => item.channel_id === args.channelId);
      if (row) {
        row.resource_id = args.resourceId;
        row.expires_at = args.expiresAt?.toISOString() ?? null;
        row.status = "active";
      }
    },
    markError: async (channelId) => {
      calls.push("mark_error");
      const row = rows.find((item) => item.channel_id === channelId);
      if (row) row.status = "error";
    },
    persistSyncToken: async (_connectionId, token) => {
      calls.push("persist_token");
      const row = [...rows].reverse().find((item) => item.status === "active") ??
        rows[rows.length - 1];
      if (row) row.sync_token = token;
    },
    copySyncToken: async (_connectionId, toChannelId) => {
      calls.push("copy_token");
      const src = rows.find((item) => item.sync_token && item.channel_id !== toChannelId);
      const dest = rows.find((item) => item.channel_id === toChannelId);
      if (src && dest && dest.sync_token == null) dest.sync_token = src.sync_token;
    },
    listWatches: async () => rows.map((item) => ({ ...item })),
    retire: async (channelId) => {
      calls.push(`retire:${channelId}`);
      const row = rows.find((item) => item.channel_id === channelId);
      if (row) row.status = "retiring";
    },
    expire: async (channelId) => {
      calls.push(`expire:${channelId}`);
      const row = rows.find((item) => item.channel_id === channelId);
      if (row) row.status = "expired";
    },
    stopChannel: async (_session, channelId) => {
      calls.push(`stop:${channelId}`);
      return true;
    },
  };
  return { rows, calls, store };
}

const oldWatch: ProviderWatch = {
  id: "w-old",
  connection_id: "conn-g",
  channel_id: "ch-old",
  resource_id: "res-old",
  channel_token: "tok-old",
  sync_token: "sync-old",
  calendar_id: "cal-1",
  status: "active",
  expires_at: "2026-09-10T12:00:00Z",
};

Deno.test("createGoogleWatch persists creating before events.watch then activates", async () => {
  const { rows, calls, store } = memoryWatches();
  const created = await createGoogleWatch({
    connectionId: "conn-g",
    calendarId: "cal-1",
    address: "https://example.test/google",
    syncToken: "sync-1",
    store,
    session: {
      fetch: async (url) => {
        assertEquals(rows[0]?.status, "creating");
        calls.push("events.watch");
        assert(url.includes("/events/watch"));
        return new Response(
          JSON.stringify({
            resourceId: "res-new",
            expiration: String(Date.parse("2026-09-16T12:00:00Z")),
          }),
          { status: 200 },
        );
      },
    },
  });
  assertEquals(calls.slice(0, 3), ["persist_creating", "events.watch", "activate"]);
  assertEquals(created.status, "active");
  assertEquals(created.resource_id, "res-new");
  assertEquals(rows[0]?.status, "active");
  assertEquals(rows[0]?.sync_token, "sync-1");
});

Deno.test("renewal creates the new watch before retiring and stopping the old channel", async () => {
  const { rows, calls, store } = memoryWatches([oldWatch]);
  const result = await renewGoogleWatch({
    connectionId: "conn-g",
    now: new Date("2026-09-09T12:00:00Z"),
    store,
    session: {
      fetch: async (url) => {
        calls.push("events.watch");
        assert(url.includes("/events/watch"));
        return new Response(
          JSON.stringify({ resourceId: "res-new", expiration: "1790000000000" }),
          { status: 200 },
        );
      },
    },
  });
  assertEquals(result.renewed, true);
  assertEquals(result.oldChannelId, "ch-old");
  assertEquals(result.stopFailed, false);
  const persistAt = calls.indexOf("persist_creating");
  const watchAt = calls.indexOf("events.watch");
  const activateAt = calls.indexOf("activate");
  const retireAt = calls.indexOf("retire:ch-old");
  const stopAt = calls.indexOf("stop:ch-old");
  const expireAt = calls.indexOf("expire:ch-old");
  assert(persistAt >= 0 && persistAt < watchAt);
  assert(watchAt < activateAt);
  assert(activateAt < retireAt);
  assert(retireAt < stopAt);
  assert(stopAt < expireAt);
  assertEquals(rows.find((item) => item.channel_id === "ch-old")?.status, "expired");
  assertEquals(rows.find((item) => item.status === "active")?.resource_id, "res-new");
});

Deno.test("failed channels.stop leaves the old watch retiring and keeps the new watch active", async () => {
  const { rows, calls, store } = memoryWatches([oldWatch]);
  store.stopChannel = async (_session, channelId) => {
    calls.push(`stop:${channelId}`);
    return false;
  };
  const result = await renewGoogleWatch({
    connectionId: "conn-g",
    now: new Date("2026-09-09T12:00:00Z"),
    store,
    session: {
      fetch: async () =>
        new Response(
          JSON.stringify({ resourceId: "res-new", expiration: "1790000000000" }),
          { status: 200 },
        ),
    },
  });
  assertEquals(result.renewed, true);
  assertEquals(result.stopFailed, true);
  assertEquals(rows.find((item) => item.channel_id === "ch-old")?.status, "retiring");
  assertEquals(rows.filter((item) => item.status === "active").length, 1);
  assertEquals(calls.includes("expire:ch-old"), false);
});

Deno.test("a second renewal attempt skips while the first watch is still creating", async () => {
  const { store } = memoryWatches([
    oldWatch,
    {
      ...oldWatch,
      id: "w-new",
      channel_id: "ch-new",
      resource_id: null,
      status: "creating",
      expires_at: null,
      sync_token: null,
    },
  ]);
  const result = await renewGoogleWatch({
    connectionId: "conn-g",
    now: new Date("2026-09-09T12:00:00Z"),
    store,
    session: {
      fetch: async () => {
        throw new Error("should not watch again");
      },
    },
  });
  assertEquals(result, { renewed: false, skipped: "creating" });
});

Deno.test("copySyncToken prefers the newest active watch", () => {
  assertEquals(
    pickSyncTokenSource(
      [
        {
          channel_id: "old",
          status: "retiring",
          sync_token: "sync-old",
          created_at: "2026-09-01T00:00:00Z",
        },
        {
          channel_id: "active",
          status: "active",
          sync_token: "sync-new",
          created_at: "2026-09-08T00:00:00Z",
        },
        {
          channel_id: "stale",
          status: "expired",
          sync_token: "sync-stale",
          created_at: "2026-09-09T00:00:00Z",
        },
      ],
      "dest",
    ),
    "sync-new",
  );
});
