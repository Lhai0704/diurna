import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";
import { readCredential, writeTokenBundle } from "./credentials.ts";
import {
  isGoogleAuthFailure,
  ReauthRequiredError,
  refreshGoogleAccessToken,
  shouldRefreshAccessToken,
} from "./google_auth.ts";
import { googleEventId } from "./google_id.ts";
import { acquireConnectionLease, persistLeaseProgress } from "./lease.ts";
import { finishPass, type JsonObject } from "./lease_logic.ts";

const WRITE_BUDGET = 80;
const NOTION_VERSION = "2026-03-11";

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
      if (link && link.sync_status === "synced" && link.last_synced_revision === revision) {
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

class GoogleSession {
  constructor(
    private readonly connectionId: string,
    private bundle: { access_token: string; refresh_token: string },
    private expiresAt: Date | null,
  ) {}

  async token(force = false): Promise<string> {
    if (force || shouldRefreshAccessToken(this.expiresAt, new Date())) {
      const next = await refreshGoogleAccessToken(this.bundle.refresh_token);
      this.bundle = {
        access_token: next.access_token,
        refresh_token: next.refresh_token || this.bundle.refresh_token,
      };
      this.expiresAt = new Date(Date.now() + next.expires_in * 1000);
      await writeTokenBundle(this.connectionId, this.bundle, this.expiresAt);
    }
    return this.bundle.access_token;
  }

  async fetch(url: string, init: RequestInit = {}): Promise<Response> {
    const headers = new Headers(init.headers);
    headers.set("Authorization", `Bearer ${await this.token()}`);
    const response = await fetch(url, { ...init, headers });
    if (!isGoogleAuthFailure(response.status)) {
      return response;
    }
    headers.set("Authorization", `Bearer ${await this.token(true)}`);
    const retried = await fetch(url, { ...init, headers });
    if (isGoogleAuthFailure(retried.status)) {
      throw new ReauthRequiredError();
    }
    return retried;
  }
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

async function createGoogleCalendar(googleAuth: GoogleSession | null): Promise<JsonObject> {
  if (!googleAuth) {
    throw new ReauthRequiredError();
  }
  const response = await googleAuth.fetch("https://www.googleapis.com/calendar/v3/calendars", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ summary: "Diurna" }),
  });
  if (!response.ok) {
    throw new Error(`google calendar create ${response.status}`);
  }
  const payload = await response.json();
  return { calendar_id: payload.id };
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
    .select("entity_id,external_id,last_synced_revision,sync_status,content_hash")
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

async function pushGoogle(args: {
  row: Record<string, unknown> & { id: string };
  link?: Link;
  tokens: string;
  connection: Record<string, unknown>;
  googleAuth: GoogleSession | null;
}) {
  if (!args.googleAuth) {
    throw new ReauthRequiredError();
  }
  const calendarId =
    ((args.connection.container as JsonObject | undefined)?.calendar_id as string | undefined) ??
    "primary";
  const eventId = args.link?.external_id ?? googleEventId(args.row.id);
  const eventDate = String(args.row.event_date).slice(0, 10);
  const end = nextDate(eventDate);
  const body = {
    id: eventId,
    summary: args.row.title,
    description: [
      args.row.note ? String(args.row.note) : "",
      args.row.is_completed ? "Completed in Diurna" : "",
    ]
      .filter((part) => part.length > 0)
      .join("\n"),
    start: { date: eventDate },
    end: { date: end },
    extendedProperties: {
      private: {
        diurnaId: args.row.id,
        diurnaRevision: String(args.row.revision ?? ""),
        diurnaCompleted: args.row.is_completed ? "true" : "false",
      },
    },
  };
  let recovered = false;
  let created = false;
  let existingId = args.link?.external_id;
  const eventUrl =
    `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calendarId)}/events`;
  if (!existingId) {
    const get = await args.googleAuth.fetch(`${eventUrl}/${eventId}`);
    if (get.ok) {
      recovered = true;
      existingId = eventId;
    }
  }
  if (existingId) {
    const patch = await args.googleAuth.fetch(`${eventUrl}/${existingId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!patch.ok) {
      throw new Error(`google patch ${patch.status}`);
    }
  } else {
    const insert = await args.googleAuth.fetch(eventUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!insert.ok) {
      throw new Error(`google insert ${insert.status}`);
    }
    created = true;
    existingId = eventId;
  }
  return {
    externalId: existingId!,
    containerId: calendarId,
    created,
    recovered,
    contentHash: null,
  };
}

async function pushNotion(args: {
  module: string;
  row: Record<string, unknown> & { id: string };
  link?: Link;
  tokens: string;
  connection: Record<string, unknown>;
}) {
  const container = (args.connection.container ?? {}) as JsonObject;
  const dataSourceId = notionDataSource(container, args.module);
  if (!dataSourceId) {
    throw new Error("notion container missing");
  }
  const properties = notionProperties(args.module, args.row);
  let recovered = false;
  let created = false;
  let pageId = args.link?.external_id;
  if (!pageId) {
    pageId = await findNotionPage(args.tokens, dataSourceId, args.row.id);
    if (pageId) {
      recovered = true;
    }
  }
  if (pageId) {
    const patch = await fetch(`https://api.notion.com/v1/pages/${pageId}`, {
      method: "PATCH",
      headers: notionHeaders(args.tokens),
      body: JSON.stringify({ properties }),
    });
    if (!patch.ok) {
      throw new Error(`notion patch ${patch.status}`);
    }
    if (args.module !== "inbox_items") {
      await replaceNotionBody(args.tokens, pageId, notionBody(args.module, args.row));
    }
  } else {
    const children = notionBody(args.module, args.row);
    const createdPage = await fetch("https://api.notion.com/v1/pages", {
      method: "POST",
      headers: notionHeaders(args.tokens),
      body: JSON.stringify({
        parent: { type: "data_source_id", data_source_id: dataSourceId },
        properties,
        children,
      }),
    });
    if (!createdPage.ok) {
      throw new Error(`notion create ${createdPage.status}`);
    }
    const payload = await createdPage.json();
    pageId = payload.id as string;
    created = true;
  }
  return {
    externalId: pageId!,
    containerId: dataSourceId,
    created,
    recovered,
    contentHash: hashText(String(args.row.content ?? args.row.note ?? "")),
  };
}

function notionDataSource(container: JsonObject, module: string): string | null {
  if (module === "inbox_items") return (container.inbox_ds as string) ?? null;
  if (module === "memos") return (container.memo_ds as string) ?? null;
  if (module === "diary_entries") return (container.diary_ds as string) ?? null;
  return null;
}

function notionHeaders(token: string): HeadersInit {
  return {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
    "Notion-Version": NOTION_VERSION,
  };
}

function notionProperties(module: string, row: Record<string, unknown>) {
  const title = String(row.content ?? row.title ?? "").slice(0, 2000);
  const base: Record<string, unknown> = {
    title: { title: [{ type: "text", text: { content: title || "Untitled" } }] },
    "Diurna ID": { rich_text: [{ type: "text", text: { content: String(row.id) } }] },
    Revision: { number: Number(row.revision ?? 1) },
    "Updated At": {
      date: { start: String(row.updated_at ?? new Date().toISOString()) },
    },
  };
  if (module === "inbox_items") {
    return {
      ...base,
      Type: row.item_type ? { select: { name: String(row.item_type) } } : { select: null },
      Column: { select: { name: String(row.inbox_column ?? "pending") } },
      Status: { select: { name: row.is_completed ? "done" : "open" } },
      Pinned: { checkbox: Boolean(row.is_pinned) },
      Archived: { checkbox: Boolean(row.is_archived) },
      Topic: { checkbox: Boolean(row.is_topic) },
    };
  }
  if (module === "diary_entries") {
    return {
      ...base,
      Date: { date: { start: String(row.entry_date).slice(0, 10) } },
      Mood: row.mood
        ? { rich_text: [{ type: "text", text: { content: String(row.mood) } }] }
        : { rich_text: [] },
    };
  }
  return base;
}

function notionBody(module: string, row: Record<string, unknown>) {
  if (module === "inbox_items") {
    return [];
  }
  const content = String(row.content ?? "");
  if (!content) {
    return [];
  }
  return content.split(/\n+/).slice(0, 100).map((line) => ({
    object: "block",
    type: "paragraph",
    paragraph: {
      rich_text: [{ type: "text", text: { content: line.slice(0, 2000) } }],
    },
  }));
}

async function replaceNotionBody(
  token: string,
  pageId: string,
  children: Array<Record<string, unknown>>,
): Promise<void> {
  const listed = await fetch(
    `https://api.notion.com/v1/blocks/${pageId}/children?page_size=100`,
    { headers: notionHeaders(token) },
  );
  if (listed.ok) {
    const payload = await listed.json();
    for (const block of payload.results ?? []) {
      if (typeof block.id !== "string") {
        continue;
      }
      await fetch(`https://api.notion.com/v1/blocks/${block.id}`, {
        method: "DELETE",
        headers: notionHeaders(token),
      });
    }
  }
  if (children.length === 0) {
    return;
  }
  const appended = await fetch(`https://api.notion.com/v1/blocks/${pageId}/children`, {
    method: "PATCH",
    headers: notionHeaders(token),
    body: JSON.stringify({ children }),
  });
  if (!appended.ok) {
    throw new Error(`notion body ${appended.status}`);
  }
}

async function findNotionPage(
  token: string,
  dataSourceId: string,
  entityId: string,
): Promise<string | null> {
  const response = await fetch(
    `https://api.notion.com/v1/data_sources/${dataSourceId}/query`,
    {
      method: "POST",
      headers: notionHeaders(token),
      body: JSON.stringify({
        filter: {
          property: "Diurna ID",
          rich_text: { equals: entityId },
        },
        page_size: 1,
      }),
    },
  );
  if (!response.ok) {
    return null;
  }
  const payload = await response.json();
  return payload.results?.[0]?.id ?? null;
}

function nextDate(isoDate: string): string {
  const date = new Date(`${isoDate}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + 1);
  return date.toISOString().slice(0, 10);
}

function hashText(value: string): string {
  return value.length.toString();
}

export { WRITE_BUDGET };
