import { json } from "./http.ts";
import {
  authenticateGoogleNotification,
  type ProviderWatch,
} from "./google_watch.ts";

export type GoogleWebhookDeps = {
  lookupWatch: (channelId: string) => Promise<ProviderWatch | null>;
  acceptWork: (args: {
    eventKey: string;
    connectionId: string;
    workType: "google_incremental" | "google_calendar_gone";
  }) => Promise<{ accepted: boolean; duplicate: boolean }>;
  recordSync: (args: { eventKey: string; connectionId: string }) => Promise<void>;
};

function header(req: Request, name: string): string | null {
  return req.headers.get(name) ?? req.headers.get(name.toLowerCase());
}

export async function handleGoogleWebhook(
  req: Request,
  deps: GoogleWebhookDeps,
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return json({ ok: true });
  }
  if (req.method !== "POST") {
    return json({ ok: false }, 405);
  }

  const channelId = header(req, "X-Goog-Channel-ID");
  const channelToken = header(req, "X-Goog-Channel-Token");
  const resourceId = header(req, "X-Goog-Resource-ID");
  const resourceState = header(req, "X-Goog-Resource-State") ?? "";
  const messageNumber = header(req, "X-Goog-Message-Number") ?? "0";

  if (!channelId) {
    return json({ ok: false, error: "unknown_channel" }, 404);
  }
  const watch = await deps.lookupWatch(channelId);
  const auth = authenticateGoogleNotification({
    channelId,
    channelToken,
    resourceId,
    watch,
  });
  if (auth === "unknown") {
    return json({ ok: false, error: "unknown_channel" }, 404);
  }
  if (auth === "unauthorized" || auth === "mismatch") {
    return json({ ok: false, error: auth }, 401);
  }
  if (!watch) {
    return json({ ok: false, error: "unknown_channel" }, 404);
  }

  const eventKey = `${channelId}:${messageNumber}`;
  if (resourceState === "sync") {
    await deps.recordSync({ eventKey, connectionId: watch.connection_id });
    return json({ ok: true, sync: true });
  }
  if (resourceState === "exists") {
    await deps.acceptWork({
      eventKey,
      connectionId: watch.connection_id,
      workType: "google_incremental",
    });
    return json({ ok: true });
  }
  if (resourceState === "not_exists") {
    await deps.acceptWork({
      eventKey,
      connectionId: watch.connection_id,
      workType: "google_calendar_gone",
    });
    return json({ ok: true, gone: true });
  }
  return json({ ok: true, ignored: true });
}
