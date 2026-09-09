import { ReauthRequiredError, type GoogleSession } from "./google_auth.ts";
import { googleEventId } from "./google_id.ts";
import type { JsonObject } from "./lease_logic.ts";

export type GooglePushLink = {
  entity_id: string;
  external_id: string;
};

export function nextDate(isoDate: string): string {
  const date = new Date(`${isoDate}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + 1);
  return date.toISOString().slice(0, 10);
}

export function googleEventBody(row: Record<string, unknown> & { id: string }, eventId: string) {
  const eventDate = String(row.event_date).slice(0, 10);
  return {
    id: eventId,
    summary: row.title,
    description: [
      row.note ? String(row.note) : "",
      row.is_completed ? "Completed in Diurna" : "",
    ]
      .filter((part) => part.length > 0)
      .join("\n"),
    start: { date: eventDate },
    end: { date: nextDate(eventDate) },
    extendedProperties: {
      private: {
        diurnaId: row.id,
        diurnaRevision: String(row.revision ?? ""),
        diurnaCompleted: row.is_completed ? "true" : "false",
      },
    },
  };
}

export async function createGoogleCalendar(
  googleAuth: GoogleSession | null,
): Promise<JsonObject> {
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

export async function pushGoogle(args: {
  row: Record<string, unknown> & { id: string };
  link?: GooglePushLink;
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
  if (!args.googleAuth) {
    throw new ReauthRequiredError();
  }
  const calendarId =
    ((args.connection.container as JsonObject | undefined)?.calendar_id as string | undefined) ??
    "primary";
  const eventId = args.link?.external_id ?? googleEventId(args.row.id);
  const body = googleEventBody(args.row, eventId);
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
