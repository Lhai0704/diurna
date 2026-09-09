import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { decideNotionBootstrapPage } from "./notion_bootstrap.ts";
import type { NotionBlock } from "./notion_import.ts";

const paragraph = (text: string): NotionBlock => ({
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
      },
    }],
  },
});

Deno.test("Notion diary bootstrap equal calendar date is ready when local entry_date is a Date", () => {
  const decision = decideNotionBootstrapPage({
    entityType: "diary_entries",
    entity: {
      title: "Day",
      content: "hello",
      entry_date: new Date("2026-09-09T00:00:00.000Z"),
      mood: "ok",
      revision: 1,
    },
    page: {
      last_edited_time: "2026-09-09T12:00:00.000Z",
      properties: {
        title: { title: [{ plain_text: "Day" }] },
        Date: { date: { start: "2026-09-09" } },
        Mood: {
          rich_text: [{
            type: "text",
            plain_text: "ok",
            text: { content: "ok" },
            annotations: {
              bold: false,
              italic: false,
              strikethrough: false,
              underline: false,
              code: false,
              color: "default",
            },
          }],
        },
      },
    },
    blocks: [paragraph("hello")],
  });
  assertEquals(decision.action, "ready");
});

Deno.test("Notion bootstrap equal mapped state is ready", () => {
  const decision = decideNotionBootstrapPage({
    entityType: "memos",
    entity: { title: "Note", content: "hello\n\nworld", revision: 1 },
    page: {
      last_edited_time: "2026-09-09T12:00:00.000Z",
      properties: {
        title: { title: [{ plain_text: "Note" }] },
        Revision: { number: 99 },
      },
    },
    blocks: [paragraph("hello"), paragraph("world")],
  });
  assertEquals(decision.action, "ready");
});

Deno.test("Notion bootstrap remote edit is bootstrap_remote_drift", () => {
  const decision = decideNotionBootstrapPage({
    entityType: "memos",
    entity: { title: "Note", content: "hello", revision: 1 },
    page: {
      last_edited_time: "2026-09-09T13:00:00.000Z",
      properties: { title: { title: [{ plain_text: "Remote" }] } },
    },
    blocks: [paragraph("hello")],
  });
  assertEquals(decision.action, "drift");
});

Deno.test("Notion bootstrap unsupported body freezes instead of baselining", () => {
  const decision = decideNotionBootstrapPage({
    entityType: "memos",
    entity: { title: "Note", content: "plain", revision: 1 },
    page: {
      properties: { title: { title: [{ plain_text: "Note" }] } },
    },
    blocks: [{ type: "heading_1", heading_1: { rich_text: [] } }],
  });
  assertEquals(decision.action, "unsupported");
});

Deno.test("legacy exporter Memo title matching content is not bootstrap_remote_drift", () => {
  const decision = decideNotionBootstrapPage({
    entityType: "memos",
    entity: { title: "Note", content: "hello\n\nworld", revision: 1 },
    page: {
      last_edited_time: "2026-09-09T12:00:00.000Z",
      properties: { title: { title: [{ plain_text: "hello\n\nworld" }] } },
    },
    blocks: [paragraph("hello"), paragraph("world")],
  });
  assertEquals(decision.action, "migrate_title");
  if (decision.action === "migrate_title") {
    assertEquals(decision.remainingDrift, false);
    assertEquals(decision.imported.patch.title, "Note");
  }
});

Deno.test("a genuinely edited remote Memo title is still drift", () => {
  const decision = decideNotionBootstrapPage({
    entityType: "memos",
    entity: { title: "Note", content: "hello\n\nworld", revision: 1 },
    page: {
      properties: { title: { title: [{ plain_text: "Edited by user" }] } },
    },
    blocks: [paragraph("hello"), paragraph("world")],
  });
  assertEquals(decision.action, "drift");
});

Deno.test("Notion bootstrap does not treat Revision as authoritative", () => {
  const withoutRevision = decideNotionBootstrapPage({
    entityType: "memos",
    entity: { title: "Note", content: "hello", revision: 4 },
    page: {
      properties: { title: { title: [{ plain_text: "Note" }] } },
    },
    blocks: [paragraph("hello")],
  });
  const withRevision = decideNotionBootstrapPage({
    entityType: "memos",
    entity: { title: "Note", content: "hello", revision: 4 },
    page: {
      properties: {
        title: { title: [{ plain_text: "Note" }] },
        Revision: { number: 1 },
      },
    },
    blocks: [paragraph("hello")],
  });
  assertEquals(withoutRevision.action, "ready");
  assertEquals(withRevision.action, "ready");
});
