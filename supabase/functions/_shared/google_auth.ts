export class ReauthRequiredError extends Error {
  readonly code = "REAUTH_REQUIRED";
  constructor(message = "Reconnect Google Calendar") {
    super(message);
    this.name = "ReauthRequiredError";
  }
}

export function shouldRefreshAccessToken(
  expiresAt: Date | null,
  now: Date,
  skewMs = 60_000,
): boolean {
  if (expiresAt == null || Number.isNaN(expiresAt.getTime())) {
    return true;
  }
  return expiresAt.getTime() <= now.getTime() + skewMs;
}

export function isGoogleAuthFailure(status: number): boolean {
  return status === 401;
}

import { writeTokenBundle } from "./credentials.ts";

export async function refreshGoogleAccessToken(refreshToken: string): Promise<{
  access_token: string;
  refresh_token?: string;
  expires_in: number;
}> {
  if (!refreshToken) {
    throw new ReauthRequiredError();
  }
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: Deno.env.get("GOOGLE_CLIENT_ID") ?? "",
      client_secret: Deno.env.get("GOOGLE_CLIENT_SECRET") ?? "",
      grant_type: "refresh_token",
      refresh_token: refreshToken,
    }),
  });
  const payload = await response.json();
  if (!response.ok || typeof payload.access_token !== "string") {
    throw new ReauthRequiredError();
  }
  return {
    access_token: payload.access_token,
    refresh_token: typeof payload.refresh_token === "string"
      ? payload.refresh_token
      : undefined,
    expires_in: Number(payload.expires_in ?? 3600),
  };
}

export class GoogleSession {
  constructor(
    private readonly connectionId: string,
    private bundle: { access_token: string; refresh_token: string },
    private expiresAt: Date | null,
    private readonly fetchImpl: typeof fetch = fetch,
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
    const response = await this.fetchImpl(url, { ...init, headers });
    if (!isGoogleAuthFailure(response.status)) {
      return response;
    }
    headers.set("Authorization", `Bearer ${await this.token(true)}`);
    const retried = await this.fetchImpl(url, { ...init, headers });
    if (isGoogleAuthFailure(retried.status)) {
      throw new ReauthRequiredError();
    }
    return retried;
  }
}
