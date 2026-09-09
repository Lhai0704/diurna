import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { readCredential } from "./credentials.ts";
import { GoogleSession, ReauthRequiredError } from "./google_auth.ts";
import { createGoogleCalendar, pushGoogle } from "./google_export.ts";
import { acquireConnectionLease, persistLeaseProgress } from "./lease.ts";
import { finishPass, type JsonObject } from "./lease_logic.ts";
import { shouldSkipOutbound } from "./outbound_skip.ts";
import { notionHeaders, pushNotion } from "./notion_export.ts";

const WRITE_BUDGET = 80;

export type ModuleCounts = {
  scanned: number;
  created: number;
  updated: number;
  skipped: number;
  failed: number;
  recovered: number;
};

const emptyCounts = (): ModuleCounts => ({
  scanned: 0,
  created: 0,
  updated: 0,
  skipped: 0,
  failed: 0,
  recovered: 0,
});

type Link = {
  entity_id: string;
  external_id: string;
  last_synced_revision: number;
  sync_status: string;
  inbound_state?: string;
  content_hash: string | null;
};

export async function runSync(args: {
  userClient: SupabaseClient;
  admin: SupabaseClient;
  userId: string;
  provider: "notion" | "google";
  runId: string | null;
}): Promise<Record<string, unknown>> {
  let connection = await loadConnection(args.admin, args.userId, args.provider);
  if (!connection) {
    return { ok: false, status: "failed", error: { code: "NOT_CONNECTED" } };
  }
  const generation = await readGeneration(args.userClient, args.userId);
  const lease = await acquireConnectionLease({
    connectionId: connection.id,
    userId: args.userId,
    incomingRunId: args.runId,
    currentGeneration: generation,
  });
  if (lease.kind === "missing") {
    return { ok: false, status: "failed", error: { code: "NOT_CONNECTED" } };
  }
  if (lease.kind === "in_progress") {
    return {
      ok: false,
      status: "failed",
      error: { code: "SYNC_IN_PROGRESS", retry_after: lease.retryAfterSeconds },
    };
  }
  if (lease.shortCircuit) {
    await persistLeaseProgress({
      connectionId: connection.id,
      userId: args.userId,
      runId: lease.runId,
      pageCursor: {},
      lastSyncStatus: "success",
      lastSyncSummary: { skipped: true, reason: "no local changes" },
      lastError: null,
      lastSeenGeneration: generation,
      clearLease: true,
      syncStartGeneration: lease.syncStartGeneration,
    });
    return {
      ok: true,
      status: "success",
      provider: args.provider,
      run_id: null,
      incomplete: false,
      modules: {},
      failures: [],
      error: null,
    };
  }

  const credential = await readCredential(connection.id);
  if (!credential) {
    return await failReauth(connection.id as string, args.userId, lease.runId);
  }
  const googleAuth = args.provider === "google"
    ? new GoogleSession(connection.id as string, credential.bundle, credential.accessExpiresAt)
    : null;
  let accessToken: string;
  try {
    accessToken = googleAuth
      ? await googleAuth.token()
      : credential.bundle.access_token;
  } catch (error) {
    if (error instanceof ReauthRequiredError) {
      return await failReauth(connection.id as string, args.userId, lease.runId);
    }
    throw error;
  }

  try {
    connection = await ensureContainer(args.admin, connection, accessToken, args.provider, googleAuth);
  } catch (error) {
    if (error instanceof ReauthRequiredError) {
      return await failReauth(connection.id as string, args.userId, lease.runId);
    }
    throw error;
  }

  const modules = enabledModules(connection, args.provider);
  const cursor = { ...(lease.pageCursor ?? {}) };
  const moduleResults: Record<string, ModuleCounts> = {};
  const failures: Array<Record<string, string>> = [];
  let writes = 0;
  let incomplete = false;

  for (const module of modules) {
    const counts = emptyCounts();
    const started = (cursor[module] as string | undefined) ?? "";
    const rows = await listRows(args.userClient, args.userId, module, started);
    const links = await loadLinks(args.admin, connection.id, module, rows.map((r) => r.id));
    for (const row of rows) {
      counts.scanned += 1;
      const link = links.get(row.id);
      const revision = Number(row.revision ?? 1);
      if (shouldSkipOutbound(link, revision)) {
        counts.skipped += 1;
        cursor[module] = row.id;
        continue;
      }
      if (writes >= WRITE_BUDGET) {
        incomplete = true;
        break;
      }
      try {
        const result = await pushRow({
          provider: args.provider,
          module,
          row,
          link,
          tokens: googleAuth ? await googleAuth.token() : accessToken,
          connection,
          googleAuth,
        });
        writes += 1;
        if (result.recovered) {
          counts.recovered += 1;
        }
        if (result.created) {
          counts.created += 1;
        } else {
          counts.updated += 1;
        }
        await args.admin.from("external_sync_links").upsert({
          user_id: args.userId,
          connection_id: connection.id,
          provider: args.provider,
          entity_type: module,
          entity_id: row.id,
          external_id: result.externalId,
          external_container_id: result.containerId,
          last_synced_revision: revision,
          content_hash: result.contentHash,
          last_synced_at: new Date().toISOString(),
          sync_status: "synced",
          last_error: null,
        }, { onConflict: "connection_id,entity_type,entity_id" });
      } catch (error) {
        if (error instanceof ReauthRequiredError) {
          return await failReauth(connection.id as string, args.userId, lease.runId);
        }
        counts.failed += 1;
        failures.push({
          entity_type: module,
          entity_id: row.id,
          code: "PROVIDER_ERROR",
          message: error instanceof Error ? error.message : "sync failed",
        });
      }
      cursor[module] = row.id;
    }
    moduleResults[module] = counts;
    if (incomplete) {
      break;
    }
    if (rows.length < WRITE_BUDGET) {
      delete cursor[module];
    } else {
      incomplete = true;
      break;
    }
  }

  const endGeneration = await readGeneration(args.userClient, args.userId);
  const hasErrors = failures.length > 0;
  if (!incomplete) {
    const done = finishPass({
      startGeneration: lease.syncStartGeneration,
      endGeneration,
      hasErrorLinks: hasErrors,
    });
    if (!done.caughtUp) {
      incomplete = true;
      for (const key of Object.keys(cursor)) {
        delete cursor[key];
      }
    }
    await persistLeaseProgress({
      connectionId: connection.id,
      userId: args.userId,
      runId: lease.runId,
      pageCursor: incomplete ? {} : {},
      lastSyncStatus: hasErrors ? "partial" : done.caughtUp ? "success" : "pending",
      lastSyncSummary: { modules: moduleResults, failures },
      lastError: hasErrors ? failures[0].message : null,
      lastSeenGeneration: done.caughtUp && !hasErrors ? endGeneration : null,
      clearLease: done.caughtUp && !hasErrors,
      syncStartGeneration: done.caughtUp ? null : lease.syncStartGeneration,
    });
    return {
      ok: true,
      status: hasErrors ? "partial" : done.caughtUp ? "success" : "partial",
      provider: args.provider,
      run_id: done.caughtUp && !hasErrors ? null : lease.runId,
      incomplete: !(done.caughtUp && !hasErrors),
      modules: moduleResults,
      failures,
      error: null,
    };
  }

  await persistLeaseProgress({
    connectionId: connection.id,
    userId: args.userId,
    runId: lease.runId,
    pageCursor: cursor,
    lastSyncStatus: hasErrors ? "partial" : "pending",
    lastSyncSummary: { modules: moduleResults, failures },
    lastError: hasErrors ? failures[0].message : null,
    lastSeenGeneration: null,
    clearLease: false,
    syncStartGeneration: lease.syncStartGeneration,
  });
  return {
    ok: true,
    status: hasErrors ? "partial" : "success",
    provider: args.provider,
    run_id: lease.runId,
    incomplete: true,
    modules: moduleResults,
    failures,
    error: null,
  };
}

async function failReauth(
  connectionId: string,
  userId: string,
  runId: string,
): Promise<Record<string, unknown>> {
  await persistLeaseProgress({
    connectionId,
    userId,
    runId,
    pageCursor: {},
    lastSyncStatus: "failed",
    lastSyncSummary: { reason: "reauth_required" },
    lastError: "REAUTH_REQUIRED",
    lastSeenGeneration: null,
    clearLease: true,
    syncStartGeneration: null,
  });
  return {
    ok: false,
    status: "failed",
    error: { code: "REAUTH_REQUIRED", message: "Reconnect Google Calendar" },
  };
}

async function ensureContainer(
  admin: SupabaseClient,
  connection: Record<string, unknown>,
  accessToken: string,
  provider: "notion" | "google",
  googleAuth: GoogleSession | null,
): Promise<Record<string, unknown>> {
  const container = (connection.container ?? {}) as JsonObject;
  if (provider === "google" && container.calendar_id) {
    return connection;
  }
  if (provider === "notion" && container.inbox_ds && container.memo_ds && container.diary_ds) {
    return connection;
  }
  const next = provider === "google"
    ? await createGoogleCalendar(googleAuth)
    : await createNotionWorkspace(accessToken);
  await admin
    .from("integration_connections")
    .update({ container: next, updated_at: new Date().toISOString() })
    .eq("id", connection.id);
  return { ...connection, container: next };
}

async function createNotionWorkspace(accessToken: string): Promise<JsonObject> {
  const page = await fetch("https://api.notion.com/v1/pages", {
    method: "POST",
    headers: notionHeaders(accessToken),
    body: JSON.stringify({
      parent: { type: "workspace", workspace: true },
      properties: {
        title: { title: [{ type: "text", text: { content: "Diurna" } }] },
      },
    }),
  });
  if (!page.ok) {
    throw new Error(`notion page create ${page.status}`);
  }
  const pagePayload = await page.json();
  const pageId = pagePayload.id as string;
  const inbox = await createNotionDatabase(accessToken, pageId, "Diurna Inbox", true);
  const memos = await createNotionDatabase(accessToken, pageId, "Diurna Memos", false);
  const diary = await createNotionDatabase(accessToken, pageId, "Diurna Diary", false);
  return {
    page_id: pageId,
    inbox_ds: inbox,
    memo_ds: memos,
    diary_ds: diary,
  };
}

async function createNotionDatabase(
  accessToken: string,
  pageId: string,
  title: string,
  inbox: boolean,
): Promise<string> {
  const properties: Record<string, unknown> = {
    title: { title: {} },
    "Diurna ID": { rich_text: {} },
    Revision: { number: {} },
    "Updated At": { date: {} },
  };
  if (inbox) {
    properties.Type = { select: { options: [
      { name: "idea" }, { name: "action" }, { name: "research" }, { name: "resource" },
    ] } };
    properties.Column = { select: { options: [{ name: "focus" }, { name: "pending" }] } };
    properties.Status = { select: { options: [{ name: "open" }, { name: "done" }] } };
    properties.Pinned = { checkbox: {} };
    properties.Archived = { checkbox: {} };
    properties.Topic = { checkbox: {} };
  }
  if (title.includes("Diary")) {
    properties.Date = { date: {} };
    properties.Mood = { rich_text: {} };
  }
  const response = await fetch("https://api.notion.com/v1/databases", {
    method: "POST",
    headers: notionHeaders(accessToken),
    body: JSON.stringify({
      parent: { type: "page_id", page_id: pageId },
      title: [{ type: "text", text: { content: title } }],
      initial_data_source: { properties },
    }),
  });
  if (!response.ok) {
    throw new Error(`notion database create ${response.status}`);
  }
  const payload = await response.json();
  return payload.data_sources?.[0]?.id ?? payload.id;
}

async function loadConnection(
  admin: SupabaseClient,
  userId: string,
  provider: string,
) {
  const { data } = await admin
    .from("integration_connections")
    .select("*")
    .eq("user_id", userId)
    .eq("provider", provider)
    .eq("status", "connected")
    .maybeSingle();
  return data as Record<string, unknown> | null;
}

async function readGeneration(client: SupabaseClient, userId: string): Promise<number> {
  const { data } = await client
    .from("diurna_sync_signals")
    .select("generation")
    .eq("user_id", userId)
    .maybeSingle();
  return Number(data?.generation ?? 0);
}

function enabledModules(
  connection: Record<string, unknown>,
  provider: string,
): string[] {
  if (provider === "google") {
    return ["calendar_events"];
  }
  const enabled = (connection.enabled_modules ?? {}) as Record<string, boolean>;
  const modules: string[] = [];
  if (enabled.inbox !== false) modules.push("inbox_items");
  if (enabled.memos !== false) modules.push("memos");
  if (enabled.diary !== false) modules.push("diary_entries");
  return modules;
}

async function listRows(
  client: SupabaseClient,
  userId: string,
  table: string,
  afterId: string,
): Promise<Array<Record<string, unknown> & { id: string }>> {
  let query = client
    .from(table)
    .select("*")
    .eq("user_id", userId)
    .order("id")
    .limit(WRITE_BUDGET);
  if (afterId) {
    query = query.gt("id", afterId);
  }
  const { data, error } = await query;
  if (error) {
    throw error;
  }
  return (data ?? []) as Array<Record<string, unknown> & { id: string }>;
}

async function loadLinks(
  admin: SupabaseClient,
  connectionId: string,
  entityType: string,
  ids: string[],
): Promise<Map<string, Link>> {
  const map = new Map<string, Link>();
  if (ids.length === 0) {
    return map;
  }
  const { data } = await admin
    .from("external_sync_links")
    .select(
      "entity_id,external_id,last_synced_revision,sync_status,inbound_state,content_hash",
    )
    .eq("connection_id", connectionId)
    .eq("entity_type", entityType)
    .in("entity_id", ids);
  for (const row of data ?? []) {
    map.set(row.entity_id as string, row as Link);
  }
  return map;
}

async function pushRow(args: {
  provider: "notion" | "google";
  module: string;
  row: Record<string, unknown> & { id: string };
  link?: Link;
  tokens: string;
  connection: Record<string, unknown>;
  googleAuth: GoogleSession | null;
}): Promise<{
  externalId: string;
  containerId: string | null;
  created: boolean;
  recovered: boolean;
  contentHash: string | null;
}> {
  if (args.provider === "google") {
    return pushGoogle(args);
  }
  return pushNotion(args);
}

export { WRITE_BUDGET };
