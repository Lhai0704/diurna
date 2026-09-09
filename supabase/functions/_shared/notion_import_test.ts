import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { patchMatchesRow } from "./mapped.ts";
import {
  flattenLosslessParagraphs,
  importNotionPage,
  isPlainParagraphBlock,
  notionBodyIsLossless,
  paragraphsFromContent,
} from "./notion_import.ts";
import { omitLegacyRemoteTitle } from "./notion_export.ts";

const paragraph = (text: string, extras: Record<string, unknown> = {}) => ({
  type: "paragraph",
  has_children: false,
  paragraph: {
    rich_text: [{
      type: "text",
      plain_text: text,
      text: { content: text },
      annotations: {
        bold: false,
        italic: false,
        strikethrough: false,
        underline: false,
        code: false,
        color: "default",
        ...((extras.annotations as object) ?? {}),
      },
      ...extras,
    }],
  },
});

Deno.test("inbox maps properties and omits unmapped fields", () => {
  const result = importNotionPage({
    entityType: "inbox_items",
    page: {
      last_edited_time: "2026-09-09T12:00:00.000Z",
      properties: {
        title: { title: [{ plain_text: "Buy milk" }] },
        Type: { select: { name: "action" } },
        Column: { select: { name: "focus" } },
        Status: { select: { name: "done" } },
        Pinned: { checkbox: true },
        Archived: { checkbox: false },
        Topic: { checkbox: false },
      },
    },
    blocks: [],
  });
  assertEquals(result.kind, "update");
  if (result.kind === "update") {
    assertEquals(result.patch.content, "Buy milk");
    assertEquals(result.patch.item_type, "action");
    assertEquals(result.patch.inbox_column, "focus");
    assertEquals(result.patch.is_completed, true);
    assertEquals(result.patch.is_pinned, true);
    assertEquals("position" in result.patch, false);
    assertEquals("due_date" in result.patch, false);
    assertEquals("parent_id" in result.patch, false);
    assertEquals("priority" in result.patch, false);
  }
});

Deno.test("memo lossless paragraphs import content", () => {
  const result = importNotionPage({
    entityType: "memos",
    page: {
      properties: { title: { title: [{ plain_text: "Note" }] } },
      last_edited_time: "2026-09-09T12:00:00.000Z",
    },
    blocks: [paragraph("hello"), paragraph("world")],
    currentContent: "other",
  });
  assertEquals(result.kind, "update");
  if (result.kind === "update") {
    assertEquals(result.patch.title, "Note");
    assertEquals(result.patch.content, "hello\n\nworld");
  }
});

Deno.test("heading body is unsupported and does not produce a patch", () => {
  const result = importNotionPage({
    entityType: "memos",
    page: {
      properties: { title: { title: [{ plain_text: "Note" }] } },
    },
    blocks: [{ type: "heading_1", heading_1: { rich_text: [] } }],
  });
  assertEquals(result.kind, "unsupported_content");
});

Deno.test("bold, link, and nested blocks are not lossless", () => {
  assertEquals(
    isPlainParagraphBlock(paragraph("x", { annotations: { bold: true } })),
    false,
  );
  assertEquals(
    isPlainParagraphBlock(paragraph("x", { text: { content: "x", link: { url: "https://x" } } })),
    false,
  );
  assertEquals(
    notionBodyIsLossless([{ type: "paragraph", has_children: true, paragraph: { rich_text: [] } }]),
    false,
  );
  assertEquals(notionBodyIsLossless([paragraph("ok")]), true);
});

Deno.test("matching paragraph split preserves existing Diurna content bytes", () => {
  const result = importNotionPage({
    entityType: "memos",
    page: { properties: { title: { title: [{ plain_text: "Note" }] } } },
    blocks: [paragraph("hello"), paragraph("world")],
    currentContent: "hello\nworld",
  });
  assertEquals(result.kind, "update");
  if (result.kind === "update") {
    assertEquals(result.patch.content, "hello\nworld");
  }
});

Deno.test("Notion Revision property is ignored by inbound mapping", () => {
  const result = importNotionPage({
    entityType: "memos",
    page: {
      properties: {
        title: { title: [{ plain_text: "Note" }] },
        Revision: { number: 12 },
      },
    },
    blocks: [paragraph("hello")],
    currentContent: "hello",
  });
  assertEquals(result.kind, "update");
  if (result.kind === "update") {
    assertEquals(result.patch.title, "Note");
    assertEquals("revision" in result.patch, false);
  }
});

Deno.test("archived page is remote_deleted", () => {
  const result = importNotionPage({
    entityType: "memos",
    page: { archived: true, properties: {} },
    blocks: [],
  });
  assertEquals(result.kind, "remote_deleted");
});

Deno.test("flatten and split helpers round-trip exporter paragraphs", () => {
  const blocks = [paragraph("a"), paragraph("b")];
  assertEquals(flattenLosslessParagraphs(blocks), "a\n\nb");
  assertEquals(paragraphsFromContent("a\n\nb"), ["a", "b"]);
  assertEquals(paragraphsFromContent("a\nb"), ["a", "b"]);
});

Deno.test("CRLF local Diary body matches LF Notion paragraphs and preserves bytes", () => {
  const currentContent = "alpha line\r\nsecond paragraph here!!!\r\nthird line ok.\r\n";
  const result = importNotionPage({
    entityType: "diary_entries",
    page: {
      properties: {
        title: { title: [{ plain_text: "2026-07-31" }] },
        Date: { date: { start: "2026-07-31" } },
        Mood: { rich_text: [] },
      },
      last_edited_time: "2026-09-09T15:06:00.000Z",
    },
    blocks: [
      paragraph("alpha line"),
      paragraph("second paragraph here!!!"),
      paragraph("third line ok."),
      paragraph(""),
    ],
    currentContent,
  });
  assertEquals(result.kind, "update");
  if (result.kind === "update") {
    assertEquals(result.patch.content, currentContent);
    assertEquals(paragraphsFromContent(currentContent).length, 4);
    const row = {
      title: "2026-07-31",
      content: currentContent,
      entry_date: "2026-07-31",
      mood: null,
    };
    const patch = omitLegacyRemoteTitle({
      entityType: "diary_entries",
      localTitle: String(row.title),
      localContent: currentContent,
      patch: result.patch,
    });
    assertEquals(patchMatchesRow(row, patch), true);
  }
});

Deno.test("lone CR and mixed CRLF/LF local content preserve exact bytes when paragraphs match", () => {
  const loneCr = importNotionPage({
    entityType: "memos",
    page: { properties: { title: { title: [{ plain_text: "Note" }] } } },
    blocks: [paragraph("a"), paragraph("b")],
    currentContent: "a\rb",
  });
  assertEquals(loneCr.kind, "update");
  if (loneCr.kind === "update") {
    assertEquals(loneCr.patch.content, "a\rb");
  }
  const mixed = importNotionPage({
    entityType: "memos",
    page: { properties: { title: { title: [{ plain_text: "Note" }] } } },
    blocks: [paragraph("a"), paragraph("b"), paragraph("c")],
    currentContent: "a\r\nb\nc",
  });
  assertEquals(mixed.kind, "update");
  if (mixed.kind === "update") {
    assertEquals(mixed.patch.content, "a\r\nb\nc");
  }
});

Deno.test("real paragraph text difference is still drift", () => {
  const result = importNotionPage({
    entityType: "diary_entries",
    page: {
      properties: {
        title: { title: [{ plain_text: "Note" }] },
        Date: { date: { start: "2026-07-31" } },
      },
    },
    blocks: [paragraph("alpha line"), paragraph("changed remotely")],
    currentContent: "alpha line\r\nsecond paragraph here!!!",
  });
  assertEquals(result.kind, "update");
  if (result.kind === "update") {
    assertEquals(result.patch.content, "alpha line\n\nchanged remotely");
    assertEquals(result.patch.content === "alpha line\r\nsecond paragraph here!!!", false);
  }
});

Deno.test("leading/trailing spaces inside a paragraph remain meaningful", () => {
  const result = importNotionPage({
    entityType: "memos",
    page: { properties: { title: { title: [{ plain_text: "Note" }] } } },
    blocks: [paragraph("hello")],
    currentContent: "hello ",
  });
  assertEquals(result.kind, "update");
  if (result.kind === "update") {
    assertEquals(result.patch.content, "hello");
  }
});
