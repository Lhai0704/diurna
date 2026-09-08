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
