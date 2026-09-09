import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  notionBody,
  notionProperties,
  omitLegacyRemoteTitle,
  patchNotionPageTitle,
} from "./notion_export.ts";

Deno.test("memo body is unannotated paragraphs split on blank lines", () => {
  const children = notionBody("memos", { content: "hello\n\nworld" });
  assertEquals(children.length, 2);
  assertEquals(children[0], {
    object: "block",
    type: "paragraph",
    paragraph: {
      rich_text: [{ type: "text", text: { content: "hello" } }],
    },
  });
  assertEquals(
    (children[1] as { paragraph: { rich_text: Array<{ text: { content: string } }> } })
      .paragraph.rich_text[0].text.content,
    "world",
  );
});

Deno.test("inbox export has no body", () => {
  assertEquals(notionBody("inbox_items", { content: "task" }), []);
});

Deno.test("inbox properties match existing exporter shape", () => {
  const properties = notionProperties("inbox_items", {
    id: "22000000-0000-0000-0000-000000000001",
    content: "Buy milk",
    item_type: "action",
    inbox_column: "focus",
    is_completed: true,
    is_pinned: true,
    is_archived: false,
    is_topic: false,
    revision: 4,
    updated_at: "2026-09-09T00:00:00Z",
  });
  assertEquals(
    (properties.Type as { select: { name: string } }).select.name,
    "action",
  );
  assertEquals(
    (properties.Status as { select: { name: string } }).select.name,
    "done",
  );
  assertEquals((properties.Pinned as { checkbox: boolean }).checkbox, true);
  assertEquals(
    (properties["Diurna ID"] as { rich_text: Array<{ text: { content: string } }> })
      .rich_text[0].text.content,
    "22000000-0000-0000-0000-000000000001",
  );
});

Deno.test("empty memo content exports no children", () => {
  assertEquals(notionBody("memos", { content: "" }), []);
});

function bodyTexts(children: unknown[]): string[] {
  return children.map((child) => {
    const block = child as { paragraph: { rich_text: Array<{ text: { content: string } }> } };
    return block.paragraph.rich_text[0].text.content;
  });
}

Deno.test("CRLF, LF, and lone CR export the same paragraph blocks without stray CR", () => {
  const lf = notionBody("diary_entries", { content: "a\nb\n" });
  const crlf = notionBody("diary_entries", { content: "a\r\nb\r\n" });
  const cr = notionBody("diary_entries", { content: "a\rb\r" });
  const mixed = notionBody("memos", { content: "a\r\nb\n" });
  assertEquals(bodyTexts(lf), ["a", "b", ""]);
  assertEquals(crlf, lf);
  assertEquals(cr, lf);
  assertEquals(mixed, lf);
  for (const children of [lf, crlf, cr, mixed]) {
    const encoded = JSON.stringify(children);
    assertEquals(encoded.includes("\\r"), false);
    assertEquals(encoded.includes("\r"), false);
  }
});

Deno.test("legacy page bootstrap then body-only inbound keeps Diurna title", async () => {
  const local = { title: "Note", content: "hello\n\nworld" };
  const afterBootstrap = omitLegacyRemoteTitle({
    entityType: "memos",
    localTitle: local.title,
    localContent: local.content,
    patch: { title: "hello\n\nworld", content: "hello\n\nworld" },
  });
  assertEquals("title" in afterBootstrap, false);

  let patchedTitle = "hello\n\nworld";
  const migrated = await patchNotionPageTitle({
    token: "t",
    pageId: "page-1",
    title: local.title,
    fetchImpl: async (_url, init) => {
      const body = JSON.parse(String(init?.body ?? "{}")) as {
        properties?: { title?: { title?: Array<{ text?: { content?: string } }> } };
      };
      patchedTitle = body.properties?.title?.title?.[0]?.text?.content ?? patchedTitle;
      return new Response(
        JSON.stringify({ last_edited_time: "2026-09-09T12:05:00.000Z" }),
        { status: 200 },
      );
    },
  });
  assertEquals(patchedTitle, "Note");
  assertEquals(migrated.lastEditedTime, "2026-09-09T12:05:00.000Z");

  const laterBodyOnly = omitLegacyRemoteTitle({
    entityType: "memos",
    localTitle: local.title,
    localContent: local.content,
    patch: { title: "hello\n\nworld", content: "hello\n\nworld\n\nps" },
  });
  assertEquals("title" in laterBodyOnly, false);
  assertEquals(laterBodyOnly.content, "hello\n\nworld\n\nps");

  const afterRemoteTitleMigrated = omitLegacyRemoteTitle({
    entityType: "memos",
    localTitle: local.title,
    localContent: "hello\n\nworld\n\nps",
    patch: { title: "Note", content: "hello\n\nworld\n\nps" },
  });
  assertEquals(afterRemoteTitleMigrated.title, "Note");
});

Deno.test("Inbox title is content; Memo/Diary title is title", () => {
  const inbox = notionProperties("inbox_items", {
    id: "i1",
    content: "Buy milk",
    title: "ignored",
  });
  const memo = notionProperties("memos", {
    id: "m1",
    title: "Note",
    content: "hello\n\nworld",
  });
  assertEquals(
    (inbox.title as { title: Array<{ text: { content: string } }> }).title[0].text.content,
    "Buy milk",
  );
  assertEquals(
    (memo.title as { title: Array<{ text: { content: string } }> }).title[0].text.content,
    "Note",
  );
});
