import { type GoogleEvent, importGoogleEvent } from "./google_import.ts";
import {
  reconcileExternalObject,
  type ReconcileInput,
  type ReconcileResult,
} from "./remote_create.ts";
import { validDate } from "./remote_identity.ts";

export async function reconcileUnlinkedGoogleEvent(args: {
  connectionId: string;
  calendarId: string;
  event: GoogleEvent;
  reconcile?: (input: ReconcileInput) => Promise<ReconcileResult>;
}): Promise<ReconcileResult> {
  const imported = importGoogleEvent(args.event);
  if (imported.kind !== "update") {
    return {
      result: "ignored",
      reason: imported.kind === "ignored" ? imported.reason : imported.kind,
    };
  }
  const start = args.event.start?.date;
  const end = args.event.end?.date;
  if (
    args.event.start?.dateTime || args.event.end?.dateTime ||
    !validDate(start) || !validDate(end) ||
    Date.parse(end) - Date.parse(start) !== 86_400_000
  ) {
    return { result: "ignored", reason: "unsupported_date_range" };
  }
  return await (args.reconcile ?? reconcileExternalObject)({
    connectionId: args.connectionId,
    provider: "google",
    containerId: args.calendarId,
    entityType: "calendar_events",
    externalId: args.event.id!,
    candidateId: args.event.extendedProperties?.private?.diurnaId,
    patch: imported.patch,
    remoteSnapshot: imported.remoteSnapshot,
    providerEtag: imported.etag,
    providerUpdatedAt: imported.updated,
  });
}
