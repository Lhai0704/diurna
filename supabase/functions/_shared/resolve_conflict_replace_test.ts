import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { GoogleSession } from "./google_auth.ts";
import type { NotionBlock } from "./notion_import.ts";
import { googleEventBody } from "./google_export.ts";
import { importGoogleEvent } from "./google_import.ts";
import {
  decideConflictResolution,
  freezeLocalSnapshot,
  listAllTopLevelBlocks,
  pushExistingGoogle,
  replaceExistingNotionPage,
} from "./resolve_conflict.ts";

const PAGE_ID = "page-keep";
const LOCAL_ROW = {
  id: "22000000-0000-0000-0000-000000000190",
  title: "Local title",
  content: "local body",
  entry_date: "2026-07-31",
  mood: "ok",
  revision: 2,
};

function diaryPage(title: string, lastEdited: string) {
  return {
    id: PAGE_ID,
    last_edited_time: lastEdited,
    archived: false,
    in_trash: false,
    properties: {
      title: {
        title: [{ type: "text", plain_text: title, text: { content: title } }],
      },
      Date: { date: { start: LOCAL_ROW.entry_date } },
      Mood: {
        rich_text: [{
          type: "text",
          plain_text: LOCAL_ROW.mood,
          text: { content: LOCAL_ROW.mood },
        }],
      },
    },
  };
}

function paragraph(id: string, text: string): NotionBlock & { id: string } {
  return {
    id,
    type: "paragraph",
    has_children: false,
    paragraph: {
      rich_text: [{ type: "text", plain_text: text, text: { content: text } }],
    },
  };
}

type MockOptions = {
  initialBlocks: Array<NotionBlock & { id: string }>;
  listStatus?: number;
  deleteStatus?: number;
  appendStatus?: number;
  patchStatus?: number;
  verifyTitle?: string;
  delete404Ids?: Set<string>;
};

function notionMock(options: MockOptions) {
  const remaining = new Map(options.initialBlocks.map((block) => [block.id, block]));
  let appended: Array<NotionBlock & { id: string }> = [];
  const deleted: string[] = [];
  let appendBody: unknown = null;
  const calls: string[] = [];

  const fetchImpl: typeof fetch = async (input, init) => {
    const url = String(input);
    const method = (init?.method ?? "GET").toUpperCase();
    calls.push(`${method} ${url}`);

    if (url.includes("/v1/pages/") && method === "PATCH") {
      if (options.patchStatus != null && options.patchStatus !== 200) {
        return new Response("no", { status: options.patchStatus });
      }
      return json({ last_edited_time: "2026-09-09T10:00:00.000Z" });
    }
    if (url.includes("/v1/pages/") && method === "GET") {
      const title = options.verifyTitle ?? LOCAL_ROW.title;
      return json(diaryPage(title, "2026-09-09T10:00:05.000Z"));
    }
    if (url.includes("/children") && method === "GET") {
      if (options.listStatus != null && options.listStatus !== 200) {
        return new Response("no", { status: options.listStatus });
      }
      const parsed = new URL(url);
      const cursor = parsed.searchParams.get("start_cursor");
      const listed = [...remaining.values(), ...appended];
      const start = cursor ? Number(cursor) : 0;
      const slice = listed.slice(start, start + 100);
      const next = start + 100;
      return json({
        results: slice,
        has_more: next < listed.length,
        next_cursor: next < listed.length ? String(next) : null,
      });
    }
    if (url.includes("/children") && method === "PATCH") {
      if (options.appendStatus != null && options.appendStatus !== 200) {
        return new Response("no", { status: options.appendStatus });
      }
      const body = JSON.parse(String(init?.body ?? "{}")) as {
        children?: NotionBlock[];
      };
      appendBody = body.children ?? [];
      appended = (body.children ?? []).map((child, index) => ({
        ...child,
        id: `new-${index}`,
        has_children: false,
        paragraph: {
          rich_text: (child.paragraph?.rich_text ?? []).map((part) => ({
            ...part,
            type: "text",
            plain_text: part.text?.content ?? part.plain_text ?? "",
          })),
        },
      }));
      return json({ results: appended });
    }
    if (method === "DELETE" && url.includes("/v1/blocks/")) {
      const blockId = url.split("/v1/blocks/")[1] ?? "";
      if (options.delete404Ids?.has(blockId)) {
        remaining.delete(blockId);
        deleted.push(blockId);
        return new Response("{}", { status: 404 });
      }
      if (options.deleteStatus != null && options.deleteStatus !== 200) {
        return new Response("no", { status: options.deleteStatus });
      }
      remaining.delete(blockId);
      deleted.push(blockId);
      return json({});
    }
    return new Response("missing", { status: 404 });
  };

  return {
    fetchImpl,
    deleted,
    remaining,
    getAppendBody: () => appendBody,
    calls,
  };
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), { status });
}

async function replace(fetchImpl: typeof fetch, row = LOCAL_ROW) {
  return await replaceExistingNotionPage({
    token: "secret-token",
    entityType: "diary_entries",
    externalId: PAGE_ID,
    row: row as Record<string, unknown> & { id: string },
    fetchImpl,
  });
}

Deno.test("listAllTopLevelBlocks paginates past 100 children", async () => {
  const blocks = Array.from({ length: 101 }, (_, i) => paragraph(`old-${i}`, `old ${i}`));
  const mock = notionMock({ initialBlocks: blocks });
  const listed = await listAllTopLevelBlocks({
    token: "t",
    pageId: PAGE_ID,
    fetchImpl: mock.fetchImpl,
  });
  assertEquals(listed.length, 101);
});

Deno.test("Keep Diurna replaces more than 100 Notion blocks and verifies", async () => {
  const blocks = Array.from({ length: 101 }, (_, i) => paragraph(`old-${i}`, `old ${i}`));
  const mock = notionMock({ initialBlocks: blocks });
  const written = await replace(mock.fetchImpl);
  assertEquals(mock.deleted.length, 101);
  assertEquals(mock.remaining.size, 0);
  assertEquals(written.updatedAt, "2026-09-09T10:00:05.000Z");
  const children = mock.getAppendBody() as Array<{ paragraph?: { rich_text?: Array<{ text?: { content?: string } }> } }>;
  assertEquals(children[0]?.paragraph?.rich_text?.[0]?.text?.content, "local body");
});

Deno.test("Notion list failure fails the resolution write", async () => {
  const mock = notionMock({
    initialBlocks: [paragraph("old-0", "old")],
    listStatus: 500,
  });
  await assertRejects(() => replace(mock.fetchImpl), Error, "notion_list_500");
  assertEquals(mock.deleted.length, 0);
});

Deno.test("Notion delete failure fails the resolution write", async () => {
  const mock = notionMock({
    initialBlocks: [paragraph("old-0", "old")],
    deleteStatus: 400,
  });
  await assertRejects(() => replace(mock.fetchImpl), Error, "notion_delete_400");
});

Deno.test("Notion append failure fails the resolution write", async () => {
  const mock = notionMock({
    initialBlocks: [paragraph("old-0", "old")],
    appendStatus: 500,
  });
  await assertRejects(() => replace(mock.fetchImpl), Error, "notion_body_500");
  assertEquals(mock.deleted, ["old-0"]);
});

Deno.test("post-write mapped mismatch leaves the write unverified", async () => {
  const mock = notionMock({
    initialBlocks: [paragraph("old-0", "old")],
    verifyTitle: "WRONG",
  });
  await assertRejects(() => replace(mock.fetchImpl), Error, "PROVIDER_VERIFY_FAILED");
});

Deno.test("successful Notion replacement uses final last_edited_time", async () => {
  const mock = notionMock({
    initialBlocks: [paragraph("old-0", "trailing")],
  });
  const written = await replace(mock.fetchImpl);
  assertEquals(written.updatedAt, "2026-09-09T10:00:05.000Z");
  assertEquals(written.updatedAt === "2026-09-09T10:00:00.000Z", false);
});

Deno.test("delete 404 is retry-safe and does not fail replacement", async () => {
  const mock = notionMock({
    initialBlocks: [paragraph("already-gone", "old")],
    delete404Ids: new Set(["already-gone"]),
  });
  const written = await replace(mock.fetchImpl);
  assertEquals(written.updatedAt, "2026-09-09T10:00:05.000Z");
});

Deno.test("frozen local snapshot is what gets written if the source mutates", async () => {
  const source = { ...LOCAL_ROW, content: "keep this" };
  const frozen = freezeLocalSnapshot(source) as Record<string, unknown> & { id: string };
  source.content = "stale mutation after snapshot";
  const mock = notionMock({ initialBlocks: [paragraph("old-0", "old")] });
  await replaceExistingNotionPage({
    token: "t",
    entityType: "diary_entries",
    externalId: PAGE_ID,
    row: frozen,
    fetchImpl: mock.fetchImpl,
  });
  const children = mock.getAppendBody() as Array<{ paragraph?: { rich_text?: Array<{ text?: { content?: string } }> } }>;
  assertEquals(children[0]?.paragraph?.rich_text?.[0]?.text?.content, "keep this");
});

function futureExpiry(): Date {
  return new Date(Date.now() + 60 * 60 * 1000);
}

Deno.test("Google Keep Diurna sends If-Match and verifies the live GET", async () => {
  const row = freezeLocalSnapshot({
    id: "22000000-0000-0000-0000-000000000194",
    title: "Warranty",
    event_date: "2027-03-01",
    note: null,
    is_completed: false,
    revision: 1,
  }) as Record<string, unknown> & { id: string };
  let ifMatch = "";
  const fetchImpl: typeof fetch = async (_input, init) => {
    const method = (init?.method ?? "GET").toUpperCase();
    if (method === "PATCH") {
      ifMatch = new Headers(init?.headers).get("If-Match") ?? "";
      const body = JSON.parse(String(init?.body ?? "{}")) as { summary?: string };
      assertEquals(body.summary, "Warranty");
      return json({ updated: "2026-09-09T10:00:00Z", etag: "stale-patch" });
    }
    return json({
      id: "gcal-1",
      status: "confirmed",
      summary: "Warranty",
      start: { date: "2027-03-01" },
      end: { date: "2027-03-02" },
      etag: "\"final-etag\"",
      updated: "2026-09-09T10:00:07Z",
    });
  };
  const written = await pushExistingGoogle({
    session: new GoogleSession("conn", { access_token: "a", refresh_token: "r" }, futureExpiry(), fetchImpl),
    calendarId: "primary",
    externalId: "gcal-1",
    row,
    ifMatchEtag: "\"live-etag\"",
  });
  assertEquals(ifMatch, "\"live-etag\"");
  assertEquals(written.etag, "\"final-etag\"");
  assertEquals(written.updatedAt, "2026-09-09T10:00:07Z");
});

Deno.test("Google provider version mismatch does not treat PATCH as success", async () => {
  const row = {
    id: "22000000-0000-0000-0000-000000000194",
    title: "Warranty",
    event_date: "2027-03-01",
    note: null,
    is_completed: false,
    revision: 1,
  } as Record<string, unknown> & { id: string };
  let patched = false;
  const fetchImpl: typeof fetch = async (_input, init) => {
    if ((init?.method ?? "GET").toUpperCase() === "PATCH") {
      patched = true;
      return new Response("precondition", { status: 412 });
    }
    throw new Error("GET should not run after 412");
  };
  await assertRejects(
    () =>
      pushExistingGoogle({
        session: new GoogleSession("conn", { access_token: "a", refresh_token: "r" }, futureExpiry(), fetchImpl),
        calendarId: "primary",
        externalId: "gcal-1",
        row,
        ifMatchEtag: "\"live-etag\"",
      }),
    Error,
    "PROVIDER_VERSION_CONFLICT",
  );
  assertEquals(patched, true);
});

Deno.test("Google post-write mapped mismatch fails verification", async () => {
  const row = {
    id: "22000000-0000-0000-0000-000000000194",
    title: "Warranty",
    event_date: "2027-03-01",
    note: null,
    is_completed: false,
    revision: 1,
  } as Record<string, unknown> & { id: string };
  const fetchImpl: typeof fetch = async (_input, init) => {
    if ((init?.method ?? "GET").toUpperCase() === "PATCH") {
      return json({ updated: "2026-09-09T10:00:00Z" });
    }
    return json({
      id: "gcal-1",
      status: "confirmed",
      summary: "Someone else won",
      start: { date: "2027-03-01" },
      etag: "\"other\"",
      updated: "2026-09-09T10:00:08Z",
    });
  };
  await assertRejects(
    () =>
      pushExistingGoogle({
        session: new GoogleSession("conn", { access_token: "a", refresh_token: "r" }, futureExpiry(), fetchImpl),
        calendarId: "primary",
        externalId: "gcal-1",
        row,
        ifMatchEtag: "\"live-etag\"",
      }),
    Error,
    "PROVIDER_VERIFY_FAILED",
  );
});

Deno.test("unsupported_recurrence never PATCHes Google and does not mutate local", async () => {
  const row = {
    id: "22000000-0000-0000-0000-000000000195",
    title: "Standup",
    event_date: "2027-04-01",
    note: null,
    is_completed: false,
    revision: 1,
  } as Record<string, unknown> & { id: string };
  const imported = importGoogleEvent({
    id: "gcal-recurring",
    summary: "Standup",
    start: { date: "2027-04-01" },
    recurrence: ["RRULE:FREQ=DAILY"],
    etag: "\"recurring\"",
  });
  assertEquals(imported.kind, "unsupported_recurrence");
  assertEquals("recurrence" in googleEventBody(row, "gcal-recurring"), false);

  let patched = false;
  const fetchImpl: typeof fetch = async (_input, init) => {
    if ((init?.method ?? "GET").toUpperCase() === "PATCH") {
      patched = true;
      throw new Error("recurrence must not PATCH");
    }
    return json({
      id: "gcal-recurring",
      summary: "Standup",
      start: { date: "2027-04-01" },
      recurrence: ["RRULE:FREQ=DAILY"],
      etag: "\"recurring\"",
    });
  };
  const decision = decideConflictResolution({
    loadResult: "ready",
    choice: "keep_local",
    liveKind: imported.kind === "unsupported_recurrence"
      ? "unsupported_recurrence"
      : "drift",
  });
  if (decision.action === "push_then_keep_local") {
    await pushExistingGoogle({
      session: new GoogleSession(
        "conn",
        { access_token: "a", refresh_token: "r" },
        futureExpiry(),
        fetchImpl,
      ),
      calendarId: "primary",
      externalId: "gcal-recurring",
      row,
      ifMatchEtag: "\"recurring\"",
    });
  }
  assertEquals(decision, { action: "error", code: "UNSUPPORTED_RECURRENCE" });
  assertEquals(patched, false);
  assertEquals(row.revision, 1);
});
