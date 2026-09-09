import { db } from "./db.ts";
import { shouldRenewWatch } from "./mapped.ts";
import { timingSafeEqual } from "./webhook_auth.ts";

export type ProviderWatch = {
  id: string;
  connection_id: string;
  channel_id: string;
  resource_id: string | null;
  channel_token: string;
  sync_token: string | null;
  calendar_id: string | null;
  status: string;
  expires_at: string | null;
};

function bytesToHex(bytes: Uint8Array): string {
  return [...bytes].map((value) => value.toString(16).padStart(2, "0")).join("");
}

export function generateWatchSecrets(): { channelId: string; channelToken: string } {
  return {
    channelId: crypto.randomUUID(),
    channelToken: bytesToHex(crypto.getRandomValues(new Uint8Array(32))),
  };
}

export function googleWebhookAddress(): string {
  const base = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  return `${base}/functions/v1/integrations-google-webhook`;
}

export async function lookupWatchByChannelId(
  channelId: string,
): Promise<ProviderWatch | null> {
  const rows = await db()`
    select id, connection_id, channel_id, resource_id, channel_token, sync_token,
           calendar_id, status, expires_at
      from integrations.provider_watches
     where channel_id = ${channelId}
     limit 1
  `;
  return (rows[0] as ProviderWatch | undefined) ?? null;
}

export async function lookupActiveWatch(
  connectionId: string,
): Promise<ProviderWatch | null> {
  const rows = await db()`
    select id, connection_id, channel_id, resource_id, channel_token, sync_token,
           calendar_id, status, expires_at
      from integrations.provider_watches
     where connection_id = ${connectionId}
       and status in ('creating', 'active', 'retiring')
     order by case status when 'active' then 0 when 'retiring' then 1 else 2 end,
              created_at desc
     limit 1
  `;
  return (rows[0] as ProviderWatch | undefined) ?? null;
}

export function authenticateGoogleNotification(args: {
  channelId: string | null;
  channelToken: string | null;
  resourceId: string | null;
  watch: ProviderWatch | null;
}): "ok" | "unknown" | "unauthorized" | "mismatch" {
  if (!args.watch) {
    return "unknown";
  }
  if (!["creating", "active", "retiring"].includes(args.watch.status)) {
    return "unauthorized";
  }
  if (!args.channelId || args.channelId !== args.watch.channel_id) {
    return "unknown";
  }
  if (!args.channelToken || !timingSafeEqual(args.channelToken, args.watch.channel_token)) {
    return "unauthorized";
  }
  if (args.watch.resource_id) {
    if (!args.resourceId || args.watch.resource_id !== args.resourceId) {
      return "mismatch";
    }
  }
  return "ok";
}

export function pickSyncTokenSource(
  watches: Array<{ channel_id: string; status: string; sync_token: string | null; created_at?: string }>,
  destChannelId: string,
): string | null {
  const ranked = watches
    .filter((item) =>
      item.channel_id !== destChannelId &&
      item.sync_token != null &&
      ["active", "retiring", "creating"].includes(item.status)
    )
    .sort((a, b) => {
      const rank = (status: string) =>
        status === "active" ? 0 : status === "retiring" ? 1 : 2;
      const byStatus = rank(a.status) - rank(b.status);
      if (byStatus !== 0) {
        return byStatus;
      }
      return String(b.created_at ?? "").localeCompare(String(a.created_at ?? ""));
    });
  return ranked[0]?.sync_token ?? null;
}

export async function persistWatchCreating(args: {
  connectionId: string;
  calendarId: string;
  channelId: string;
  channelToken: string;
}): Promise<ProviderWatch> {
  const rows = await db()`
    insert into integrations.provider_watches (
      connection_id, provider, channel_id, channel_token, calendar_id, status
    ) values (
      ${args.connectionId}::uuid, 'google', ${args.channelId}, ${args.channelToken},
      ${args.calendarId}, 'creating'
    )
    returning id, connection_id, channel_id, resource_id, channel_token, sync_token,
              calendar_id, status, expires_at
  `;
  return rows[0] as ProviderWatch;
}

export async function activateWatch(args: {
  channelId: string;
  resourceId: string;
  expiresAt: Date | null;
}): Promise<void> {
  await db()`
    update integrations.provider_watches
       set resource_id = ${args.resourceId},
           expires_at = ${args.expiresAt},
           status = 'active',
           last_error = null,
           updated_at = now()
     where channel_id = ${args.channelId}
       and status = 'creating'
  `;
}

export async function markWatchError(channelId: string, error: string): Promise<void> {
  await db()`
    update integrations.provider_watches
       set status = 'error', last_error = ${error}, updated_at = now()
     where channel_id = ${channelId}
  `;
}

export async function persistWatchSyncToken(
  connectionId: string,
  syncToken: string,
): Promise<void> {
  await db()`
    update integrations.provider_watches
       set sync_token = ${syncToken},
           last_incremental_at = now(),
           updated_at = now()
     where id = (
       select id from integrations.provider_watches
        where connection_id = ${connectionId}::uuid
        order by case status when 'active' then 0 when 'creating' then 1 else 2 end,
                 created_at desc
        limit 1
     )
  `;
}

export async function lookupSyncToken(connectionId: string): Promise<string | null> {
  const rows = await db()`
    select sync_token
      from integrations.provider_watches
     where connection_id = ${connectionId}::uuid
       and sync_token is not null
     order by case status when 'active' then 0 when 'creating' then 1 else 2 end,
              created_at desc
     limit 1
  `;
  return (rows[0]?.sync_token as string | undefined) ?? null;
}

export async function listConnectionWatches(connectionId: string): Promise<ProviderWatch[]> {
  const rows = await db()`
    select id, connection_id, channel_id, resource_id, channel_token, sync_token,
           calendar_id, status, expires_at
      from integrations.provider_watches
     where connection_id = ${connectionId}::uuid
     order by created_at
  `;
  return rows as unknown as ProviderWatch[];
}

export type GoogleFetcher = {
  fetch: (url: string, init?: RequestInit) => Promise<Response>;
};

export type WatchPersistence = {
  persistCreating: typeof persistWatchCreating;
  activate: typeof activateWatch;
  markError: typeof markWatchError;
  persistSyncToken: typeof persistWatchSyncToken;
  copySyncToken: (connectionId: string, toChannelId: string) => Promise<void>;
  listWatches: typeof listConnectionWatches;
  retire: typeof retireWatch;
  expire: typeof expireWatch;
  stopChannel: (session: GoogleFetcher, channelId: string, resourceId: string) => Promise<boolean>;
};

export type WatchRenewalDecision =
  | { action: "skip"; reason: "creating" | "no_calendar" | "not_due" }
  | { action: "create_missing" }
  | { action: "renew"; oldChannelId: string; calendarId: string };

export function decideWatchRenewal(args: {
  watches: Array<{
    status: string;
    expires_at: string | null;
    channel_id: string;
    calendar_id: string | null;
  }>;
  now: Date;
}): WatchRenewalDecision {
  if (args.watches.some((item) => item.status === "creating")) {
    return { action: "skip", reason: "creating" };
  }
  const active = [...args.watches].reverse().find((item) => item.status === "active");
  if (!active) {
    return { action: "create_missing" };
  }
  if (!active.calendar_id) {
    return { action: "skip", reason: "no_calendar" };
  }
  if (
    !shouldRenewWatch({
      now: args.now,
      expiresAt: active.expires_at,
      status: active.status,
      hasCreating: false,
    })
  ) {
    return { action: "skip", reason: "not_due" };
  }
  return {
    action: "renew",
    oldChannelId: active.channel_id,
    calendarId: active.calendar_id,
  };
}

export async function retireWatch(channelId: string): Promise<void> {
  await db()`
    update integrations.provider_watches
       set status = 'retiring', updated_at = now()
     where channel_id = ${channelId}
       and status = 'active'
  `;
}

export async function expireWatch(channelId: string): Promise<void> {
  await db()`
    update integrations.provider_watches
       set status = 'expired', updated_at = now()
     where channel_id = ${channelId}
       and status in ('retiring', 'creating', 'active')
  `;
}

async function copySyncToken(connectionId: string, toChannelId: string): Promise<void> {
  const watches = await db()`
    select channel_id, status, sync_token, created_at
      from integrations.provider_watches
     where connection_id = ${connectionId}::uuid
     order by created_at
  ` as Array<{
    channel_id: string;
    status: string;
    sync_token: string | null;
    created_at: string;
  }>;
  const token = pickSyncTokenSource(watches, toChannelId);
  if (!token) {
    return;
  }
  await db()`
    update integrations.provider_watches
       set sync_token = ${token},
           updated_at = now()
     where channel_id = ${toChannelId}
       and sync_token is null
  `;
}

export async function stopChannel(
  session: GoogleFetcher,
  channelId: string,
  resourceId: string,
): Promise<boolean> {
  try {
    const response = await session.fetch(
      "https://www.googleapis.com/calendar/v3/channels/stop",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id: channelId, resourceId }),
      },
    );
    return response.ok || response.status === 404;
  } catch {
    return false;
  }
}

function defaultWatchPersistence(): WatchPersistence {
  return {
    persistCreating: persistWatchCreating,
    activate: activateWatch,
    markError: markWatchError,
    persistSyncToken: persistWatchSyncToken,
    copySyncToken,
    listWatches: listConnectionWatches,
    retire: retireWatch,
    expire: expireWatch,
    stopChannel,
  };
}

export async function createGoogleWatch(args: {
  connectionId: string;
  calendarId: string;
  session: GoogleFetcher;
  address?: string;
  syncToken?: string | null;
  store?: Partial<WatchPersistence>;
}): Promise<ProviderWatch> {
  const store = { ...defaultWatchPersistence(), ...args.store };
  const secrets = generateWatchSecrets();
  const watch = await store.persistCreating({
    connectionId: args.connectionId,
    calendarId: args.calendarId,
    channelId: secrets.channelId,
    channelToken: secrets.channelToken,
  });
  const address = args.address ?? googleWebhookAddress();
  const response = await args.session.fetch(
    `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(args.calendarId)}/events/watch`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        id: secrets.channelId,
        type: "web_hook",
        address,
        token: secrets.channelToken,
        params: { ttl: "604800" },
      }),
    },
  );
  if (!response.ok) {
    const error = `watch_${response.status}`;
    await store.markError(secrets.channelId, error);
    throw new Error(error);
  }
  const payload = await response.json() as {
    resourceId?: string;
    expiration?: string | number;
  };
  const resourceId = payload.resourceId;
  if (!resourceId) {
    await store.markError(secrets.channelId, "watch_missing_resource");
    throw new Error("watch_missing_resource");
  }
  const expiresAt = payload.expiration != null
    ? new Date(Number(payload.expiration))
    : null;
  const resolvedExpiry = expiresAt ?? new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
  await store.activate({
    channelId: secrets.channelId,
    resourceId,
    expiresAt: resolvedExpiry,
  });
  if (args.syncToken) {
    await store.persistSyncToken(args.connectionId, args.syncToken);
  } else {
    await store.copySyncToken(args.connectionId, secrets.channelId);
  }
  return {
    ...watch,
    resource_id: resourceId,
    status: "active",
    expires_at: resolvedExpiry.toISOString(),
  };
}

export async function renewGoogleWatch(args: {
  connectionId: string;
  session: GoogleFetcher;
  now?: Date;
  calendarId?: string | null;
  store?: Partial<WatchPersistence>;
}): Promise<{
  renewed: boolean;
  skipped?: string;
  newChannelId?: string;
  oldChannelId?: string;
  stopFailed?: boolean;
}> {
  const store = { ...defaultWatchPersistence(), ...args.store };
  const now = args.now ?? new Date();
  const watches = await store.listWatches(args.connectionId);
  const decision = decideWatchRenewal({ watches, now });
  if (decision.action === "skip") {
    return { renewed: false, skipped: decision.reason };
  }
  const calendarId = decision.action === "renew"
    ? decision.calendarId
    : args.calendarId ?? watches.find((item) => item.calendar_id)?.calendar_id ?? null;
  if (!calendarId) {
    return { renewed: false, skipped: "no_calendar" };
  }
  const created = await createGoogleWatch({
    connectionId: args.connectionId,
    calendarId,
    session: args.session,
    store,
  });
  const toRetire = decision.action === "renew"
    ? watches.filter((item) =>
      item.status === "active" && item.channel_id !== created.channel_id
    )
    : [];
  let stopFailed = false;
  for (const old of toRetire) {
    await store.retire(old.channel_id);
    if (old.resource_id) {
      const stopped = await store.stopChannel(
        args.session,
        old.channel_id,
        old.resource_id,
      );
      if (stopped) {
        await store.expire(old.channel_id);
      } else {
        stopFailed = true;
      }
    }
  }
  return {
    renewed: true,
    newChannelId: created.channel_id,
    oldChannelId: decision.action === "renew" ? decision.oldChannelId : undefined,
    stopFailed,
  };
}

export async function retryRetiringStops(args: {
  sessionFor: (connectionId: string) => Promise<GoogleFetcher | null>;
  now?: Date;
}): Promise<number> {
  const cutoff = new Date((args.now ?? new Date()).getTime() - 60 * 60 * 1000);
  const rows = await db()`
    select connection_id, channel_id, resource_id
      from integrations.provider_watches
     where status = 'retiring'
       and updated_at < ${cutoff}
  `;
  let stopped = 0;
  for (const row of rows) {
    const session = await args.sessionFor(String(row.connection_id));
    if (!session || !row.resource_id) {
      continue;
    }
    const ok = await stopChannel(session, String(row.channel_id), String(row.resource_id));
    if (ok) {
      await expireWatch(String(row.channel_id));
      stopped += 1;
    }
  }
  return stopped;
}

export async function stopGoogleWatches(
  connectionId: string,
  session: GoogleFetcher | null,
): Promise<void> {
  const rows = await db()`
    select channel_id, resource_id, status
      from integrations.provider_watches
     where connection_id = ${connectionId}::uuid
       and status in ('creating', 'active', 'retiring')
  `;
  for (const row of rows) {
    if (session && row.resource_id && row.channel_id) {
      try {
        await session.fetch("https://www.googleapis.com/calendar/v3/channels/stop", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            id: row.channel_id,
            resourceId: row.resource_id,
          }),
        });
      } catch {
        // Disconnect must not fail because Google stop is unavailable.
      }
    }
    await db()`
      update integrations.provider_watches
         set status = 'expired', updated_at = now()
       where channel_id = ${row.channel_id as string}
    `;
  }
}
