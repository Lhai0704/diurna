import { readCredential } from "./credentials.ts";
import { db } from "./db.ts";
import {
  applyExternalChange,
  freezeLinkConflict,
} from "./external_mutation.ts";
import { GoogleSession, ReauthRequiredError } from "./google_auth.ts";
import { importGoogleEvent, type GoogleEvent } from "./google_import.ts";
import { touchInboundOk } from "./connection_status.ts";
import {
  lookupActiveWatch,
  lookupSyncToken,
  persistWatchSyncToken,
} from "./google_watch.ts";


type LinkRow = {
  entity_type: string;
  entity_id: string;
  external_id: string;
  inbound_state: string;
  external_etag: string | null;
};

async function loadConnection(connectionId: string): Promise<Record<string, unknown> | null> {
  const rows = await db()`
    select id, user_id, status, container, inbound_status
      from public.integration_connections
     where id = ${connectionId}::uuid
     limit 1
  `;
  return (rows[0] as Record<string, unknown> | undefined) ?? null;
}

async function loadLinkByExternalId(
  connectionId: string,
  externalId: string,
): Promise<LinkRow | null> {
  const rows = await db()`
    select entity_type, entity_id, external_id, inbound_state, external_etag
      from public.external_sync_links
     where connection_id = ${connectionId}::uuid
       and external_id = ${externalId}
     limit 1
  `;
  return (rows[0] as LinkRow | undefined) ?? null;
}

export async function listGoogleEvents(args: {
  fetch: (url: string) => Promise<Response>;
  calendarId: string;
  syncToken: string | null;
}): Promise<{ items: GoogleEvent[]; nextSyncToken: string | null; fullResync: boolean }> {
  const items: GoogleEvent[] = [];
  let syncToken = args.syncToken;
  let pageToken: string | null = null;
  let fullResync = false;
  let nextSyncToken: string | null = null;

  const requestOnce = async (
    token: string | null,
    page: string | null,
  ): Promise<Response> => {
    const url = new URL(
      `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(args.calendarId)}/events`,
    );
    url.searchParams.set("maxResults", "250");
    url.searchParams.set("showDeleted", "true");
    if (token) {
      url.searchParams.set("syncToken", token);
    }
    if (page) {
      url.searchParams.set("pageToken", page);
    }
    return await args.fetch(url.toString());
  };

  let response = await requestOnce(syncToken, pageToken);
  if (response.status === 410) {
    fullResync = true;
    syncToken = null;
    pageToken = null;
    items.length = 0;
    response = await requestOnce(null, null);
  }
  if (!response.ok) {
    throw new Error(`google_list_${response.status}`);
  }

  while (true) {
    const payload = await response.json() as {
      items?: GoogleEvent[];
      nextPageToken?: string;
      nextSyncToken?: string;
    };
    items.push(...(payload.items ?? []));
    if (payload.nextPageToken) {
      pageToken = payload.nextPageToken;
      response = await requestOnce(syncToken, pageToken);
      if (response.status === 410) {
        fullResync = true;
        syncToken = null;
        pageToken = null;
        items.length = 0;
        response = await requestOnce(null, null);
        if (!response.ok) {
          throw new Error(`google_list_${response.status}`);
        }
        continue;
      }
      if (!response.ok) {
        throw new Error(`google_list_${response.status}`);
      }
      continue;
    }
    nextSyncToken = payload.nextSyncToken ?? null;
    break;
  }

  return { items, nextSyncToken, fullResync };
}

export async function applyGoogleEvent(
  connectionId: string,
  event: GoogleEvent,
): Promise<{ result: string; reason?: string }> {
  const eventId = typeof event.id === "string" ? event.id : "";
  if (!eventId) {
    return { result: "ignored", reason: "missing_id" };
  }
  const link = await loadLinkByExternalId(connectionId, eventId);
  if (!link || link.entity_type !== "calendar_events") {
    return { result: "ignored", reason: "no_link" };
  }
  const imported = importGoogleEvent(event);
  if (imported.kind === "ignored") {
    return { result: "ignored", reason: imported.reason };
  }
  if (imported.kind === "remote_deleted") {
    const applied = await applyExternalChange({
      connectionId,
      entityType: link.entity_type,
      entityId: link.entity_id,
      externalId: link.external_id,
      operation: "remote_deleted",
      patch: {},
      remoteSnapshot: imported.remoteSnapshot,
      providerEtag: imported.etag,
      providerUpdatedAt: imported.updated,
    });
    return { result: applied.result, reason: applied.reason };
  }
  if (
    imported.kind === "unsupported_timed_event" ||
    imported.kind === "unsupported_recurrence"
  ) {
    const frozen = await freezeLinkConflict({
      connectionId,
      entityType: link.entity_type,
      entityId: link.entity_id,
      externalId: link.external_id,
      reason: imported.kind,
      remoteSnapshot: imported.remoteSnapshot,
      providerEtag: imported.etag,
      providerUpdatedAt: imported.updated,
    });
    return { result: frozen.result, reason: frozen.reason };
  }
  if (imported.kind !== "update") {
    return { result: "ignored", reason: "unhandled" };
  }
  const applied = await applyExternalChange({
    connectionId,
    entityType: link.entity_type,
    entityId: link.entity_id,
    externalId: link.external_id,
    operation: "update",
    patch: imported.patch,
    remoteSnapshot: imported.remoteSnapshot,
    providerEtag: imported.etag,
    providerUpdatedAt: imported.updated,
  });
  return { result: applied.result, reason: applied.reason };
}

export async function processGoogleIncrementalWork(args: {
  connectionId: string;
  session?: GoogleSession;
}): Promise<{ result: string; applied: number; fullResync: boolean }> {
  const connection = await loadConnection(args.connectionId);
    if (!connection || connection.status !== "connected") {
      return { result: "ignored", applied: 0, fullResync: false };
    }
    const inboundStatus = String(connection.inbound_status ?? "disabled");
    if (inboundStatus === "disabled" || inboundStatus === "bootstrapping") {
      return { result: "deferred", applied: 0, fullResync: false };
    }
    if (inboundStatus === "error") {
      return { result: "ignored", applied: 0, fullResync: false };
    }
    const watch = await lookupActiveWatch(args.connectionId);
    const calendarId =
      watch?.calendar_id ??
      ((connection.container as { calendar_id?: string } | undefined)?.calendar_id) ??
      null;
    if (!calendarId) {
      return { result: "ignored", applied: 0, fullResync: false };
    }
    let session = args.session;
    if (!session) {
      const credential = await readCredential(args.connectionId);
      if (!credential) {
        throw new ReauthRequiredError();
      }
      session = new GoogleSession(
        args.connectionId,
        credential.bundle,
        credential.accessExpiresAt,
      );
    }
    const listed = await listGoogleEvents({
      fetch: (url) => session.fetch(url),
      calendarId,
      syncToken: watch?.sync_token ?? (await lookupSyncToken(args.connectionId)),
    });
    let applied = 0;
    for (const item of listed.items) {
      const outcome = await applyGoogleEvent(args.connectionId, item);
      if (outcome.result === "applied") {
        applied += 1;
      }
    }
    if (listed.nextSyncToken) {
      await persistWatchSyncToken(args.connectionId, listed.nextSyncToken);
    }
    await touchInboundOk(args.connectionId, listed.fullResync ? "full_resync" : "incremental");
    await db()`
      update public.integration_connections
         set inbound_delta_hold = false,
             updated_at = now()
       where id = ${args.connectionId}::uuid
    `;
    return {
      result: "ok",
      applied,
      fullResync: listed.fullResync,
    };
}

export async function processGoogleCalendarGone(
  connectionId: string,
): Promise<{ result: string }> {
  await db()`
    update public.integration_connections
       set inbound_status = 'error',
           inbound_error = 'CALENDAR_GONE',
           last_inbound_result = 'error',
           updated_at = now()
     where id = ${connectionId}::uuid
  `;
  await db()`
    update integrations.provider_watches
       set status = 'error', last_error = 'CALENDAR_GONE', updated_at = now()
     where connection_id = ${connectionId}::uuid
       and status in ('creating', 'active', 'retiring')
  `;
  return { result: "calendar_gone" };
}
