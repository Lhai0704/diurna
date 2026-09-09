import { readCredential } from "./credentials.ts";
import { db } from "./db.ts";
import {
  applyExternalChange,
  bootstrapLinkVersion,
  freezeLinkConflict,
} from "./external_mutation.ts";
import { GoogleSession, ReauthRequiredError } from "./google_auth.ts";
import {
  importGoogleEvent,
  type GoogleEvent,
  type GoogleImportResult,
} from "./google_import.ts";
import { createGoogleWatch, persistWatchSyncToken } from "./google_watch.ts";
import { listGoogleEvents } from "./google_worker.ts";
import { loadConnectionRow, setInboundStatus } from "./connection_status.ts";
import { patchMatchesRow } from "./mapped.ts";

async function loadCalendarLinks(connectionId: string) {
  return await db()`
    select l.entity_id::text as entity_id, l.external_id, l.last_synced_revision,
           e.title, e.event_date::text as event_date, e.note, e.revision
      from public.external_sync_links l
      join public.calendar_events e on e.id = l.entity_id and e.user_id = l.user_id
     where l.connection_id = ${connectionId}::uuid
       and l.entity_type = 'calendar_events'
  ` as Array<{
    entity_id: string;
    external_id: string;
    last_synced_revision: number;
    title: string;
    event_date: string;
    note: string | null;
    revision: number;
  }>;
}

export type GoogleBootstrapDecision =
  | {
    action: "ready";
    imported: Extract<GoogleImportResult, { kind: "update" }>;
  }
  | {
    action: "drift";
    imported: Extract<GoogleImportResult, { kind: "update" }>;
  }
  | {
    action: "unsupported";
    reason: "unsupported_timed_event" | "unsupported_recurrence";
    imported: Extract<
      GoogleImportResult,
      { kind: "unsupported_timed_event" | "unsupported_recurrence" }
    >;
  }
  | {
    action: "remote_deleted";
    missing: boolean;
    imported: Extract<GoogleImportResult, { kind: "remote_deleted" }> | null;
  }
  | { action: "ignored"; reason: string };

export function decideGoogleBootstrapLink(args: {
  remote: GoogleEvent | undefined;
  row: Record<string, unknown>;
}): GoogleBootstrapDecision {
  if (!args.remote || args.remote.deleted === true || args.remote.status === "cancelled") {
    const imported = args.remote ? importGoogleEvent(args.remote) : null;
    return {
      action: "remote_deleted",
      missing: !args.remote,
      imported: imported && imported.kind === "remote_deleted" ? imported : null,
    };
  }
  const imported = importGoogleEvent(args.remote);
  if (
    imported.kind === "unsupported_timed_event" ||
    imported.kind === "unsupported_recurrence"
  ) {
    return { action: "unsupported", reason: imported.kind, imported };
  }
  if (imported.kind === "remote_deleted") {
    return { action: "remote_deleted", missing: false, imported };
  }
  if (imported.kind !== "update") {
    return {
      action: "ignored",
      reason: imported.kind === "ignored" ? imported.reason : "unhandled",
    };
  }
  return {
    action: patchMatchesRow(args.row, imported.patch) ? "ready" : "drift",
    imported,
  };
}

export async function bootstrapGoogleConnection(args: {
  connectionId: string;
  session?: GoogleSession;
  createWatch?: boolean;
}): Promise<{ result: string; ready: number; conflicts: number; watch: string }> {
  const connection = await loadConnectionRow(args.connectionId);
  if (!connection || connection.status !== "connected") {
    return { result: "ignored", ready: 0, conflicts: 0, watch: "skipped" };
  }
  const latest = await loadConnectionRow(args.connectionId);
    if (!latest || latest.status !== "connected") {
      return { result: "ignored", ready: 0, conflicts: 0, watch: "skipped" };
    }
    await setInboundStatus(args.connectionId, "bootstrap_start");
    const calendarId =
      ((latest.container as { calendar_id?: string } | undefined)?.calendar_id) ?? null;
    if (!calendarId) {
      await setInboundStatus(args.connectionId, "calendar_gone", { error: "missing_calendar" });
      return { result: "error", ready: 0, conflicts: 0, watch: "skipped" };
    }
    let session = args.session;
    if (!session) {
      const credential = await readCredential(args.connectionId);
      if (!credential) {
        await setInboundStatus(args.connectionId, "reauth", { error: "REAUTH_REQUIRED" });
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
      syncToken: null,
    });
    const remoteById = new Map<string, GoogleEvent>();
    for (const item of listed.items) {
      if (typeof item.id === "string") {
        remoteById.set(item.id, item);
      }
    }
    const links = await loadCalendarLinks(args.connectionId);
    let ready = 0;
    let conflicts = 0;
    for (const link of links) {
      const remote = remoteById.get(link.external_id);
      const row = {
        title: link.title,
        event_date: String(link.event_date).slice(0, 10),
        note: link.note,
        revision: link.revision,
      };
      const decision = decideGoogleBootstrapLink({ remote, row });
      if (decision.action === "ignored") {
        continue;
      }
      if (decision.action === "remote_deleted") {
        const applied = await applyExternalChange({
          connectionId: args.connectionId,
          entityType: "calendar_events",
          entityId: link.entity_id,
          externalId: link.external_id,
          operation: "remote_deleted",
          patch: {},
          remoteSnapshot: decision.imported?.remoteSnapshot ?? {
            id: link.external_id,
            missing: decision.missing,
          },
          providerEtag: decision.imported?.etag ?? null,
          providerUpdatedAt: decision.imported?.updated ?? null,
        });
        if (applied.result === "conflict") {
          conflicts += 1;
        }
        continue;
      }
      if (decision.action === "unsupported") {
        await freezeLinkConflict({
          connectionId: args.connectionId,
          entityType: "calendar_events",
          entityId: link.entity_id,
          externalId: link.external_id,
          reason: decision.reason,
          remoteSnapshot: decision.imported.remoteSnapshot,
          providerEtag: decision.imported.etag,
          providerUpdatedAt: decision.imported.updated,
        });
        conflicts += 1;
        continue;
      }
      const bootstrapped = await bootstrapLinkVersion({
        connectionId: args.connectionId,
        entityType: "calendar_events",
        entityId: link.entity_id,
        externalId: link.external_id,
        providerEtag: decision.imported.etag,
        providerUpdatedAt: decision.imported.updated,
        drift: decision.action === "drift",
        reason: decision.action === "drift" ? "bootstrap_remote_drift" : undefined,
        localSnapshot: row,
        remoteSnapshot: decision.imported.remoteSnapshot,
      });
      if (bootstrapped.result === "conflict") {
        conflicts += 1;
      } else {
        ready += 1;
      }
    }
    // nextSyncToken is stored only after the compare pass finishes.
    let watch = "skipped";
    if (args.createWatch !== false) {
      try {
        await createGoogleWatch({
          connectionId: args.connectionId,
          calendarId,
          session,
          syncToken: listed.nextSyncToken,
        });
        watch = "created";
        await setInboundStatus(args.connectionId, "bootstrap_ok_watch_ok", {
          result: "bootstrap",
        });
      } catch {
        watch = "failed";
        if (listed.nextSyncToken) {
          await persistWatchSyncToken(args.connectionId, listed.nextSyncToken);
        }
        await setInboundStatus(args.connectionId, "bootstrap_ok_watch_failed", {
          error: "WATCH_FAILED",
          result: "bootstrap",
        });
      }
    } else if (listed.nextSyncToken) {
      await persistWatchSyncToken(args.connectionId, listed.nextSyncToken);
      await setInboundStatus(args.connectionId, "bootstrap_ok_watch_ok", {
        result: "bootstrap",
      });
    } else {
      await setInboundStatus(args.connectionId, "bootstrap_ok_watch_ok", {
        result: "bootstrap",
      });
    }
  return { result: "ok", ready, conflicts, watch };
}
