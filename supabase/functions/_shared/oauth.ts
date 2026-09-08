import { consumeOauthState, insertOauthState, writeTokenBundle } from "./credentials.ts";

const NOTION_VERSION = "2026-03-11";

export function appOrigin(): string {
  const origin = Deno.env.get("APP_ORIGIN") ?? "";
  return origin.replace(/\/$/, "");
}

export function serviceRoleKey(): string {
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) {
    return legacy;
  }
  const parsed = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}") as {
    default?: string;
  };
  if (!parsed.default) {
    throw new Error("service role key is not configured");
  }
  return parsed.default;
}

export function callbackUrl(): string {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  if (!supabaseUrl) {
    throw new Error("SUPABASE_URL is not configured");
  }
  return `${supabaseUrl.replace(/\/$/, "")}/functions/v1/integrations-oauth-callback`;
}

export async function startOauth(args: {
  userId: string;
  provider: "notion" | "google";
}): Promise<string> {
  const state = crypto.randomUUID();
  const codeVerifier = args.provider === "google" ? generateVerifier() : null;
  await insertOauthState({
    state,
    userId: args.userId,
    provider: args.provider,
    codeVerifier,
    returnTo: appOrigin(),
    expiresAt: new Date(Date.now() + 10 * 60 * 1000),
  });
  const redirectUri = encodeURIComponent(callbackUrl());
  if (args.provider === "notion") {
    const clientId = Deno.env.get("NOTION_CLIENT_ID");
    if (!clientId) {
      throw new Error("NOTION_CLIENT_ID is not configured");
    }
    return `https://api.notion.com/v1/oauth/authorize?owner=user&client_id=${encodeURIComponent(clientId)}&response_type=code&redirect_uri=${redirectUri}&state=${state}`;
  }
  const clientId = Deno.env.get("GOOGLE_CLIENT_ID");
  if (!clientId || !codeVerifier) {
    throw new Error("GOOGLE_CLIENT_ID is not configured");
  }
  const challenge = await pkceChallenge(codeVerifier);
  const scope = encodeURIComponent(
    "https://www.googleapis.com/auth/calendar.app.created",
  );
  return `https://accounts.google.com/o/oauth2/v2/auth?client_id=${encodeURIComponent(clientId)}&redirect_uri=${redirectUri}&response_type=code&scope=${scope}&state=${state}&access_type=offline&prompt=consent&code_challenge=${challenge}&code_challenge_method=S256`;
}

export async function finishOauth(args: {
  code: string;
  state: string;
}): Promise<{ userId: string; provider: string; returnTo: string }> {
  const saved = await consumeOauthState(args.state);
  if (!saved) {
    throw new Error("invalid_state");
  }
  if (saved.provider === "notion") {
    await exchangeNotion(args.code, saved.user_id);
  } else {
    await exchangeGoogle(args.code, saved.user_id, saved.code_verifier);
  }
  return {
    userId: saved.user_id,
    provider: saved.provider,
    returnTo: saved.return_to || appOrigin(),
  };
}

async function exchangeNotion(code: string, userId: string): Promise<void> {
  const clientId = Deno.env.get("NOTION_CLIENT_ID") ?? "";
  const clientSecret = Deno.env.get("NOTION_CLIENT_SECRET") ?? "";
  const basic = btoa(`${clientId}:${clientSecret}`);
  const response = await fetch("https://api.notion.com/v1/oauth/token", {
    method: "POST",
    headers: {
      Authorization: `Basic ${basic}`,
      "Content-Type": "application/json",
      "Notion-Version": NOTION_VERSION,
    },
    body: JSON.stringify({
      grant_type: "authorization_code",
      code,
      redirect_uri: callbackUrl(),
    }),
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error("notion_token_failed");
  }
  await persistConnection({
    userId,
    provider: "notion",
    displayName: payload.workspace_name ?? "Notion",
    providerAccountId: payload.workspace_id ?? payload.bot_id,
    scopes: [],
    accessToken: payload.access_token,
    refreshToken: payload.refresh_token ?? payload.access_token,
    expiresAt: null,
  });
}

async function exchangeGoogle(
  code: string,
  userId: string,
  codeVerifier: string | null,
): Promise<void> {
  const body = new URLSearchParams({
    client_id: Deno.env.get("GOOGLE_CLIENT_ID") ?? "",
    client_secret: Deno.env.get("GOOGLE_CLIENT_SECRET") ?? "",
    code,
    grant_type: "authorization_code",
    redirect_uri: callbackUrl(),
  });
  if (codeVerifier) {
    body.set("code_verifier", codeVerifier);
  }
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error("google_token_failed");
  }
  const expiresAt = payload.expires_in
    ? new Date(Date.now() + Number(payload.expires_in) * 1000)
    : null;
  await persistConnection({
    userId,
    provider: "google",
    displayName: "Diurna",
    providerAccountId: null,
    scopes: ["https://www.googleapis.com/auth/calendar.app.created"],
    accessToken: payload.access_token,
    refreshToken: payload.refresh_token ?? "",
    expiresAt,
  });
}

async function persistConnection(args: {
  userId: string;
  provider: "notion" | "google";
  displayName: string;
  providerAccountId: string | null;
  scopes: string[];
  accessToken: string;
  refreshToken: string;
  expiresAt: Date | null;
}): Promise<void> {
  const { createClient } = await import("npm:@supabase/supabase-js@2");
  const admin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    serviceRoleKey(),
    { auth: { persistSession: false } },
  );
  const existing = await admin
    .from("integration_connections")
    .select("id")
    .eq("user_id", args.userId)
    .eq("provider", args.provider)
    .in("status", ["pending", "connected", "error", "disconnected"])
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  const row = {
    user_id: args.userId,
    provider: args.provider,
    status: "connected",
    display_name: args.displayName,
    provider_account_id: args.providerAccountId,
    granted_scopes: args.scopes,
    token_expires_at: args.expiresAt?.toISOString() ?? null,
    last_sync_status: "never",
    last_seen_generation: null,
    page_cursor: {},
    updated_at: new Date().toISOString(),
  };
  let connectionId = existing.data?.id as string | undefined;
  if (connectionId) {
    await admin.from("integration_connections").update(row).eq("id", connectionId);
  } else {
    const inserted = await admin
      .from("integration_connections")
      .insert(row)
      .select("id")
      .single();
    connectionId = inserted.data?.id as string;
  }
  if (!connectionId) {
    throw new Error("connection_persist_failed");
  }
  await writeTokenBundle(
    connectionId,
    { access_token: args.accessToken, refresh_token: args.refreshToken },
    args.expiresAt,
  );
}

function generateVerifier(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

async function pkceChallenge(verifier: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(verifier),
  );
  return btoa(String.fromCharCode(...new Uint8Array(digest)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}
