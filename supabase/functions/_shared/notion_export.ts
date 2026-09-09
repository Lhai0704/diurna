import type { JsonObject } from "./lease_logic.ts";

export const NOTION_VERSION = "2026-03-11";

export type NotionPushLink = {
  entity_id: string;
  external_id: string;
};

export function notionHeaders(token: string): HeadersInit {
  return {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
    "Notion-Version": NOTION_VERSION,
  };
}

export function notionDataSource(
  container: JsonObject,
  module: string,
): string | null {
  if (module === "inbox_items") return (container.inbox_ds as string) ?? null;
  if (module === "memos") return (container.memo_ds as string) ?? null;
  if (module === "diary_entries") return (container.diary_ds as string) ?? null;
  return null;
}

export function notionTitleFromRow(module: string, row: Record<string, unknown>): string {
  if (module === "inbox_items") {
    return String(row.content ?? "").slice(0, 2000);
  }
  return String(row.title ?? "").slice(0, 2000);
}

/** Old exporter used `content ?? title` for every module, including Memo/Diary. */
export function legacyExportedNotionTitle(row: Record<string, unknown>): string {
  return String(row.content ?? row.title ?? "").slice(0, 2000);
}

export function omitLegacyRemoteTitle(args: {
  entityType: string;
  localTitle: string;
  localContent: string;
  patch: Record<string, unknown>;
}): Record<string, unknown> {
  const remoteTitle = String(args.patch.title ?? "");
  if (
    !("title" in args.patch) ||
    !isLegacyMemoDiaryTitle({
      entityType: args.entityType,
      localTitle: args.localTitle,
      localContent: args.localContent,
      remoteTitle,
    })
  ) {
    return args.patch;
  }
  const next = { ...args.patch };
  delete next.title;
  return next;
}

export async function patchNotionPageTitle(args: {
  token: string;
  pageId: string;
  title: string;
  fetchImpl?: (input: string, init?: RequestInit) => Promise<Response>;
}): Promise<{ lastEditedTime: string | null }> {
  const fetchImpl = args.fetchImpl ?? fetch;
  const response = await fetchImpl(`https://api.notion.com/v1/pages/${args.pageId}`, {
    method: "PATCH",
    headers: notionHeaders(args.token),
    body: JSON.stringify({
      properties: {
        title: {
          title: [{
            type: "text",
            text: { content: args.title.slice(0, 2000) || "Untitled" },
          }],
        },
      },
    }),
  });
  if (!response.ok) {
    throw new Error(`notion_title_patch_${response.status}`);
  }
  const payload = await response.json() as { last_edited_time?: string };
  return { lastEditedTime: payload.last_edited_time ?? null };
}

export function isLegacyMemoDiaryTitle(args: {
  entityType: string;
  localTitle: string;
  localContent: string;
  remoteTitle: string;
}): boolean {
  if (args.entityType !== "memos" && args.entityType !== "diary_entries") {
    return false;
  }
  const remote = args.remoteTitle || "Untitled";
  const localTitle = args.localTitle || "Untitled";
  if (remote === localTitle) {
    return false;
  }
  const oldExported = (args.localContent || args.localTitle || "").slice(0, 2000) ||
    "Untitled";
  return remote === oldExported;
}

export function notionProperties(module: string, row: Record<string, unknown>) {
  const title = notionTitleFromRow(module, row);
  const base: Record<string, unknown> = {
    title: { title: [{ type: "text", text: { content: title || "Untitled" } }] },
    "Diurna ID": { rich_text: [{ type: "text", text: { content: String(row.id) } }] },
    Revision: { number: Number(row.revision ?? 1) },
    "Updated At": {
      date: { start: String(row.updated_at ?? new Date().toISOString()) },
    },
  };
  if (module === "inbox_items") {
    return {
      ...base,
      Type: row.item_type ? { select: { name: String(row.item_type) } } : { select: null },
      Column: { select: { name: String(row.inbox_column ?? "pending") } },
      Status: { select: { name: row.is_completed ? "done" : "open" } },
      Pinned: { checkbox: Boolean(row.is_pinned) },
      Archived: { checkbox: Boolean(row.is_archived) },
      Topic: { checkbox: Boolean(row.is_topic) },
    };
  }
  if (module === "diary_entries") {
    return {
      ...base,
      Date: { date: { start: String(row.entry_date).slice(0, 10) } },
      Mood: row.mood
        ? { rich_text: [{ type: "text", text: { content: String(row.mood) } }] }
        : { rich_text: [] },
    };
  }
  return base;
}

export function notionBody(module: string, row: Record<string, unknown>) {
  if (module === "inbox_items") {
    return [];
  }
  const content = String(row.content ?? "");
  if (!content) {
    return [];
  }
  return content.split(/\n+/).slice(0, 100).map((line) => ({
    object: "block",
    type: "paragraph",
    paragraph: {
      rich_text: [{ type: "text", text: { content: line.slice(0, 2000) } }],
    },
  }));
}

export async function replaceNotionBody(
  token: string,
  pageId: string,
  children: Array<Record<string, unknown>>,
): Promise<void> {
  const listed = await fetch(
    `https://api.notion.com/v1/blocks/${pageId}/children?page_size=100`,
    { headers: notionHeaders(token) },
  );
  if (listed.ok) {
    const payload = await listed.json();
    for (const block of payload.results ?? []) {
      if (typeof block.id !== "string") {
        continue;
      }
      await fetch(`https://api.notion.com/v1/blocks/${block.id}`, {
        method: "DELETE",
        headers: notionHeaders(token),
      });
    }
  }
  if (children.length === 0) {
    return;
  }
  const appended = await fetch(`https://api.notion.com/v1/blocks/${pageId}/children`, {
    method: "PATCH",
    headers: notionHeaders(token),
    body: JSON.stringify({ children }),
  });
  if (!appended.ok) {
    throw new Error(`notion body ${appended.status}`);
  }
}

export async function findNotionPage(
  token: string,
  dataSourceId: string,
  entityId: string,
): Promise<string | null> {
  const response = await fetch(
    `https://api.notion.com/v1/data_sources/${dataSourceId}/query`,
    {
      method: "POST",
      headers: notionHeaders(token),
      body: JSON.stringify({
        filter: {
          property: "Diurna ID",
          rich_text: { equals: entityId },
        },
        page_size: 1,
      }),
    },
  );
  if (!response.ok) {
    return null;
  }
  const payload = await response.json();
  return payload.results?.[0]?.id ?? null;
}

function hashText(value: string): string {
  return value.length.toString();
}

export async function pushNotion(args: {
  module: string;
  row: Record<string, unknown> & { id: string };
  link?: NotionPushLink;
  tokens: string;
  connection: Record<string, unknown>;
}): Promise<{
  externalId: string;
  containerId: string | null;
  created: boolean;
  recovered: boolean;
  contentHash: string | null;
}> {
  const container = (args.connection.container ?? {}) as JsonObject;
  const dataSourceId = notionDataSource(container, args.module);
  if (!dataSourceId) {
    throw new Error("notion container missing");
  }
  const properties = notionProperties(args.module, args.row);
  let recovered = false;
  let created = false;
  let pageId: string | undefined = args.link?.external_id;
  if (!pageId) {
    const found = await findNotionPage(args.tokens, dataSourceId, args.row.id);
    if (found) {
      recovered = true;
      pageId = found;
    }
  }
  if (pageId) {
    const patch = await fetch(`https://api.notion.com/v1/pages/${pageId}`, {
      method: "PATCH",
      headers: notionHeaders(args.tokens),
      body: JSON.stringify({ properties }),
    });
    if (!patch.ok) {
      throw new Error(`notion patch ${patch.status}`);
    }
    if (args.module !== "inbox_items") {
      await replaceNotionBody(args.tokens, pageId, notionBody(args.module, args.row));
    }
  } else {
    const children = notionBody(args.module, args.row);
    const createdPage = await fetch("https://api.notion.com/v1/pages", {
      method: "POST",
      headers: notionHeaders(args.tokens),
      body: JSON.stringify({
        parent: { type: "data_source_id", data_source_id: dataSourceId },
        properties,
        children,
      }),
    });
    if (!createdPage.ok) {
      throw new Error(`notion create ${createdPage.status}`);
    }
    const payload = await createdPage.json();
    pageId = payload.id as string;
    created = true;
  }
  return {
    externalId: pageId!,
    containerId: dataSourceId,
    created,
    recovered,
    contentHash: hashText(String(args.row.content ?? args.row.note ?? "")),
  };
}
