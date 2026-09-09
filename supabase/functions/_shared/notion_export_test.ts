import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { notionBody, notionProperties } from "./notion_export.ts";

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
