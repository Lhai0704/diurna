import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { diurnaId, notionId, validDate } from "./remote_identity.ts";
import { reconcileUnlinkedGoogleEvent } from "./google_remote_create.ts";
import {
  notionDiurnaId,
  notionEntityType,
  reconcileUnlinkedNotionPage,
  resolveNotionSource,
} from "./notion_remote_create.ts";
import { queryDataSource } from "./notion_discovery.ts";
import type { GoogleEvent } from "./google_import.ts";
import type { ReconcileInput } from "./remote_create.ts";
import { NOTION_INBOUND_EVENTS } from "./notion_webhook.ts";

const id = "10000000-0000-0000-0000-000000000001";
const allDay: GoogleEvent = {
  id: "manual",
  summary: "Day",
  start: { date: "2026-09-10" },
  end: { date: "2026-09-11" },
};
const paragraph = (content: string) => ({
  type: "paragraph",
  paragraph: { rich_text: [{ type: "text", text: { content } }] },
});

Deno.test("remote identity parsing and Notion source classification", () => {
  assertEquals(diurnaId(id.toUpperCase()), id);
  for (const value of [null, "", "not-uuid", id.replaceAll("-", "")]) {
    assertEquals(diurnaId(value), null);
  }
  assertEquals(notionId(id.replaceAll("-", "")), id);
  assertEquals(
    notionEntityType({ inbox_ds: id }, id.replaceAll("-", "")),
    "inbox_items",
  );
  assertEquals(notionEntityType({ inbox_ds: id, memo_ds: id }, id), null);
  assertEquals(notionEntityType({ memo_ds: id }, "other"), null);
  assert(!validDate("2026-02-30"));
  assert(NOTION_INBOUND_EVENTS.has("page.created"));
});

Deno.test("Google remote-create classifies supported event before database mutation", async () => {
  const calls: ReconcileInput[] = [];
  const reconcile = async (input: ReconcileInput) => {
    calls.push(input);
    return { result: "created", entity_id: id };
  };
  assertEquals(
    (await reconcileUnlinkedGoogleEvent({
      connectionId: id,
      calendarId: "managed",
      event: allDay,
      reconcile,
    })).result,
    "created",
  );
  assertEquals(calls[0].containerId, "managed");
  assertEquals(calls[0].patch, { event_date: "2026-09-10", title: "Day" });
  await reconcileUnlinkedGoogleEvent({
    connectionId: id,
    calendarId: "managed",
    event: { ...allDay, extendedProperties: { private: { diurnaId: id } } },
    reconcile,
  });
  assertEquals(calls[1].candidateId, id);
  for (
    const event of [
      { ...allDay, start: { dateTime: "2026-09-10T00:00:00Z" } },
      { ...allDay, recurrence: ["RRULE:FREQ=DAILY"] },
      { ...allDay, recurringEventId: "series" },
      { ...allDay, status: "cancelled" },
      { ...allDay, deleted: true },
      { ...allDay, end: { date: "2026-09-12" } },
      { ...allDay, end: { date: "2026-02-30" } },
    ]
  ) {
    assertEquals(
      (await reconcileUnlinkedGoogleEvent({
        connectionId: id,
        calendarId: "managed",
        event,
        reconcile,
      })).result,
      "ignored",
    );
  }
  assertEquals(calls.length, 2);
});

Deno.test("Notion remote create losslessly maps all three modules", async () => {
  const calls: ReconcileInput[] = [];
  const reconcile = async (input: ReconcileInput) => {
    calls.push(input);
    return { result: "created", entity_id: id };
  };
  const properties = {
    title: { title: [{ text: { content: "Title" } }] },
    Date: { date: { start: "2026-09-10" } },
    Mood: { rich_text: [{ text: { content: "happy" } }] },
  };
  for (const entityType of ["inbox_items", "memos", "diary_entries"]) {
    const result = await reconcileUnlinkedNotionPage({
      connectionId: id,
      sourceId: id,
      entityType,
      page: { id, properties },
      blocks: entityType === "inbox_items"
        ? []
        : [paragraph("one"), paragraph("two")],
      reconcile,
    });
    assertEquals(result.result, "created");
  }
  assertEquals(calls[0].patch, { content: "Title" });
  assertEquals(calls[1].patch, { title: "Title", content: "one\n\ntwo" });
  assertEquals(calls[2].patch, {
    title: "Title",
    content: "one\n\ntwo",
    entry_date: "2026-09-10",
    mood: "happy",
  });
  assertEquals(
    notionDiurnaId({
      properties: { "Diurna ID": { rich_text: [{ text: { content: id } }] } },
    }),
    id,
  );
  assertEquals(
    notionDiurnaId({
      properties: {
        "Diurna ID": { rich_text: [{ text: { content: "invalid" } }] },
      },
    }),
    null,
  );
});

Deno.test("unsupported Notion body cannot truncate; later supported body retries", async () => {
  let calls = 0;
  const reconcile = async () => {
    calls++;
    return { result: "created" };
  };
  for (
    const blocks of [[{ type: "heading_1" }], [{
      ...paragraph("nested"),
      has_children: true,
    }], [paragraph("x".repeat(2001))]]
  ) {
    const result = await reconcileUnlinkedNotionPage({
      connectionId: id,
      sourceId: id,
      entityType: "memos",
      page: { id },
      blocks,
      reconcile,
    });
    assertEquals(result.reason, "unsupported_content");
  }
  assertEquals(
    (await reconcileUnlinkedNotionPage({
      connectionId: id,
      sourceId: id,
      entityType: "inbox_items",
      page: { id },
      blocks: [paragraph("body")],
      reconcile,
    })).reason,
    "unsupported_content",
  );
  assertEquals(calls, 0);
  await reconcileUnlinkedNotionPage({
    connectionId: id,
    sourceId: id,
    entityType: "memos",
    page: { id },
    blocks: [paragraph("supported")],
    reconcile,
  });
  assertEquals(calls, 1);
});

Deno.test("Notion actual parent bounds and legacy database source resolution", async () => {
  let calls = 0;
  const fetchImpl = async () => {
    calls++;
    return Response.json({ data_sources: [{ id }] });
  };
  assertEquals(
    await resolveNotionSource(
      { parent: { type: "page_id" } },
      { memo_ds: id },
      "test",
      fetchImpl,
    ),
    null,
  );
  assertEquals(
    await resolveNotionSource(
      { parent: { type: "data_source_id", data_source_id: "foreign" } },
      { memo_ds: id },
      "test",
      fetchImpl,
    ),
    null,
  );
  assertEquals(calls, 0);
  assertEquals(
    await resolveNotionSource(
      { parent: { type: "database_id", database_id: "db" } },
      { memo_ds: id },
      "test",
      fetchImpl,
    ),
    id,
  );
  assertEquals(
    await resolveNotionSource(
      { parent: { type: "database_id", database_id: "db" } },
      { memo_ds: id },
      "test",
      async () => Response.json({ data_sources: [{ id }, { id: "another" }] }),
    ),
    null,
  );
});

Deno.test("Notion bounded history query continues at cursor and incremental uses timestamp", async () => {
  const bodies: Array<Record<string, unknown>> = [];
  const fetchImpl = async (_url: string, init?: RequestInit) => {
    bodies.push(JSON.parse(String(init?.body)));
    return Response.json({
      results: [{ id }],
      has_more: true,
      next_cursor: `cursor-${bodies.length}`,
    });
  };
  const batch = await queryDataSource({
    token: "test",
    dataSourceId: id,
    fetchImpl,
  });
  assertEquals(bodies.length, 3);
  assertEquals(batch.nextCursor, "cursor-3");
  assertEquals(bodies[0].filter, undefined);
  await queryDataSource({
    token: "test",
    dataSourceId: id,
    fetchImpl,
    startCursor: batch.nextCursor,
    sinceIso: "2026-09-10T00:00:00Z",
  });
  assertEquals(bodies[3].start_cursor, "cursor-3");
  assert(bodies[3].filter);
});
