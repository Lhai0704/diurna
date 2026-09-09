const COMPLETED_FOOTER = "Completed in Diurna";

export type GoogleEvent = {
  id?: string;
  status?: string;
  summary?: string;
  description?: string;
  etag?: string;
  updated?: string;
  start?: { date?: string; dateTime?: string; timeZone?: string };
  end?: { date?: string; dateTime?: string };
  recurrence?: string[];
  recurringEventId?: string;
  deleted?: boolean;
  extendedProperties?: { private?: Record<string, string> };
};

export type GoogleImportResult =
  | {
    kind: "update";
    patch: Record<string, unknown>;
    etag: string | null;
    updated: string | null;
    remoteSnapshot: Record<string, unknown>;
  }
  | {
    kind: "unsupported_timed_event" | "unsupported_recurrence";
    etag: string | null;
    updated: string | null;
    remoteSnapshot: Record<string, unknown>;
  }
  | {
    kind: "remote_deleted";
    etag: string | null;
    updated: string | null;
    remoteSnapshot: Record<string, unknown>;
  }
  | { kind: "ignored"; reason: string };

export function noteFromGoogleDescription(description: string | undefined): string | undefined {
  if (description == null) {
    return undefined;
  }
  const lines = description.split("\n");
  if (lines[lines.length - 1] === COMPLETED_FOOTER) {
    lines.pop();
    while (lines.length > 0 && lines[lines.length - 1] === "") {
      lines.pop();
    }
  }
  return lines.join("\n");
}

export function importGoogleEvent(event: GoogleEvent): GoogleImportResult {
  const eventId = typeof event.id === "string" ? event.id : "";
  const etag = typeof event.etag === "string" ? event.etag : null;
  const updated = typeof event.updated === "string" ? event.updated : null;
  const snapshot: Record<string, unknown> = {
    id: eventId,
    etag,
    updated,
    status: event.status,
  };

  if (event.deleted === true || event.status === "cancelled") {
    return {
      kind: "remote_deleted",
      etag,
      updated,
      remoteSnapshot: snapshot,
    };
  }
  if (!eventId) {
    return { kind: "ignored", reason: "missing_id" };
  }

  if (
    (Array.isArray(event.recurrence) && event.recurrence.length > 0) ||
    (typeof event.recurringEventId === "string" && event.recurringEventId.length > 0)
  ) {
    return {
      kind: "unsupported_recurrence",
      etag,
      updated,
      remoteSnapshot: { ...snapshot, recurrence: event.recurrence, recurringEventId: event.recurringEventId },
    };
  }

  const hasDateTime = typeof event.start?.dateTime === "string" &&
    event.start.dateTime.length > 0;
  const hasDate = typeof event.start?.date === "string" && event.start.date.length > 0;
  if (hasDateTime && !hasDate) {
    return {
      kind: "unsupported_timed_event",
      etag,
      updated,
      remoteSnapshot: { ...snapshot, start: event.start },
    };
  }
  if (!hasDate) {
    return { kind: "ignored", reason: "missing_start_date" };
  }

  const patch: Record<string, unknown> = {
    event_date: event.start!.date!.slice(0, 10),
  };
  if (typeof event.summary === "string") {
    patch.title = event.summary;
  }
  const note = noteFromGoogleDescription(event.description);
  if (note != null) {
    patch.note = note.length > 0 ? note : null;
  }

  return {
    kind: "update",
    patch,
    etag,
    updated,
    remoteSnapshot: { ...snapshot, patch },
  };
}
