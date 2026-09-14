import { json } from "./http.ts";
import {
  parseNotionVerificationHandshake,
  verifyNotionSignature,
} from "./webhook_auth.ts";

export const NOTION_INBOUND_EVENTS = new Set([
  "page.created",
  "page.properties_updated",
  "page.content_updated",
  "page.deleted",
  "page.undeleted",
]);

export type NotionWebhookEvent = {
  id?: string;
  type?: string;
  workspace_id?: string;
  entity?: { id?: string; type?: string };
};

export type NotionWebhookDeps = {
  loadVerificationToken: () => Promise<string | null>;
  acceptHandshake: (args: {
    verificationToken: string;
    setupNonce: string | null;
  }) => Promise<"stored" | "rejected">;
  lookupConnectionIds: (args: {
    workspaceId: string | null;
    pageId: string | null;
  }) => Promise<string[]>;
  acceptEvent: (args: {
    eventKey: string;
    connectionId: string;
    pageId: string;
    eventType: string;
    workspaceId: string | null;
  }) => Promise<{ accepted: boolean; duplicate: boolean }>;
};

function pageIdFromEvent(event: NotionWebhookEvent): string | null {
  const id = event.entity?.id;
  return typeof id === "string" && id.length > 0 ? id : null;
}

export async function handleNotionWebhook(
  req: Request,
  deps: NotionWebhookDeps,
): Promise<Response> {
  if (req.method === "OPTIONS") {
    return json({ ok: true });
  }
  if (req.method !== "POST") {
    return json({ ok: false }, 405);
  }

  const rawBody = await req.text();
  const handshake = parseNotionVerificationHandshake(rawBody);
  if (handshake) {
    let setupNonce: string | null = null;
    try {
      setupNonce = new URL(req.url).searchParams.get("setup");
    } catch {
      setupNonce = null;
    }
    const accepted = await deps.acceptHandshake({
      verificationToken: handshake,
      setupNonce,
    });
    if (accepted !== "stored") {
      return json({ ok: false, error: "handshake_rejected" }, 401);
    }
    return new Response(null, { status: 200 });
  }

  const token = await deps.loadVerificationToken();
  if (!token) {
    return json({ ok: false, error: "unverified" }, 401);
  }
  const signature = req.headers.get("X-Notion-Signature") ??
    req.headers.get("x-notion-signature");
  const trusted = await verifyNotionSignature({
    rawBody,
    signatureHeader: signature,
    verificationToken: token,
  });
  if (!trusted) {
    return json({ ok: false, error: "invalid_signature" }, 401);
  }

  let event: NotionWebhookEvent;
  try {
    event = JSON.parse(rawBody) as NotionWebhookEvent;
  } catch {
    return json({ ok: false, error: "invalid_json" }, 400);
  }

  if (!event.type || !NOTION_INBOUND_EVENTS.has(event.type)) {
    return json({ ok: true, ignored: true });
  }
  const eventId = typeof event.id === "string" ? event.id : null;
  const pageId = pageIdFromEvent(event);
  if (!eventId || !pageId) {
    return json({ ok: true, ignored: true });
  }

  const connectionIds = await deps.lookupConnectionIds({
    workspaceId: typeof event.workspace_id === "string" ? event.workspace_id : null,
    pageId,
  });
  if (connectionIds.length === 0) {
    return json({ ok: true, ignored: true });
  }

  for (const connectionId of connectionIds) {
    await deps.acceptEvent({
      eventKey: `${eventId}:${connectionId}`,
      connectionId,
      pageId,
      eventType: event.type,
      workspaceId: typeof event.workspace_id === "string" ? event.workspace_id : null,
    });
  }
  return json({ ok: true });
}
