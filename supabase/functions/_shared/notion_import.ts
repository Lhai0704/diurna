import {
  MAX_NOTION_PARAGRAPHS,
  MAX_NOTION_TEXT,
  notionParagraphsFromContent,
  notionParagraphSequencesEqual,
  normalizeNotionLineEndings,
} from "./notion_text.ts";

const INBOX_TYPES = new Set(["idea", "action", "research", "resource"]);
const INBOX_COLUMNS = new Set(["focus", "pending"]);
const MAX_PARAGRAPHS = MAX_NOTION_PARAGRAPHS;
const MAX_TEXT = MAX_NOTION_TEXT;

export type NotionRichText = {
  type?: string;
  plain_text?: string;
  text?: { content?: string; link?: unknown };
  annotations?: {
    bold?: boolean;
    italic?: boolean;
    strikethrough?: boolean;
    underline?: boolean;
    code?: boolean;
    color?: string;
  };
};

export type NotionBlock = {
  type?: string;
  has_children?: boolean;
  paragraph?: { rich_text?: NotionRichText[] };
  [key: string]: unknown;
};

export type NotionPage = {
  parent?: { type?: string; data_source_id?: string; database_id?: string };
  id?: string;
  archived?: boolean;
  in_trash?: boolean;
  last_edited_time?: string;
  properties?: Record<string, unknown>;
};

export type NotionImportResult =
  | {
    kind: "update";
    entityType: "inbox_items" | "memos" | "diary_entries";
    patch: Record<string, unknown>;
    lastEditedTime: string | null;
    remoteSnapshot: Record<string, unknown>;
  }
  | {
    kind: "unsupported_content";
    entityType: "inbox_items" | "memos" | "diary_entries";
    lastEditedTime: string | null;
    remoteSnapshot: Record<string, unknown>;
  }
  | { kind: "remote_deleted"; lastEditedTime: string | null };

function titleText(properties: Record<string, unknown> | undefined): string {
  const title = properties?.title as { title?: NotionRichText[] } | undefined;
  return flattenRichText(title?.title ?? []);
}

function flattenRichText(parts: NotionRichText[]): string {
  return parts.map((part) => part.plain_text ?? part.text?.content ?? "").join("");
}

function selectName(value: unknown): string | null {
  const name = (value as { select?: { name?: string } | null } | undefined)?.select?.name;
  return typeof name === "string" && name.length > 0 ? name : null;
}

function checkboxValue(value: unknown): boolean | null {
  const box = (value as { checkbox?: boolean } | undefined)?.checkbox;
  return typeof box === "boolean" ? box : null;
}

function richTextValue(value: unknown): string | null {
  const parts = (value as { rich_text?: NotionRichText[] } | undefined)?.rich_text;
  if (!Array.isArray(parts)) {
    return null;
  }
  return flattenRichText(parts);
}

function dateValue(value: unknown): string | null {
  const start = (value as { date?: { start?: string } | null } | undefined)?.date?.start;
  return typeof start === "string" && start.length > 0 ? start.slice(0, 10) : null;
}

export function isPlainParagraphBlock(block: NotionBlock): boolean {
  if (block.type !== "paragraph") {
    return false;
  }
  if (block.has_children) {
    return false;
  }
  const rich = block.paragraph?.rich_text ?? [];
  for (const part of rich) {
    if (part.type != null && part.type !== "text") {
      return false;
    }
    if (part.text?.link != null) {
      return false;
    }
    const annotations = part.annotations ?? {};
    if (
      annotations.bold ||
      annotations.italic ||
      annotations.strikethrough ||
      annotations.underline ||
      annotations.code
    ) {
      return false;
    }
    if (annotations.color != null && annotations.color !== "default") {
      return false;
    }
  }
  return true;
}

export function notionBodyIsLossless(blocks: NotionBlock[]): boolean {
  if (blocks.length > MAX_PARAGRAPHS) {
    return false;
  }
  return blocks.every((block) => isPlainParagraphBlock(block) &&
    normalizeNotionLineEndings(flattenRichText(block.paragraph?.rich_text ?? [])).length <= MAX_TEXT);
}

export function flattenLosslessParagraphs(blocks: NotionBlock[]): string {
  return blocks.map((block) => {
    const text = normalizeNotionLineEndings(
      flattenRichText(block.paragraph?.rich_text ?? []),
    );
    return text.slice(0, MAX_TEXT);
  }).join("\n\n");
}

export function paragraphsFromContent(content: string): string[] {
  return notionParagraphsFromContent(content);
}

export function entityTypeForModule(
  entityType: string,
): "inbox_items" | "memos" | "diary_entries" | null {
  if (
    entityType === "inbox_items" ||
    entityType === "memos" ||
    entityType === "diary_entries"
  ) {
    return entityType;
  }
  return null;
}

export function importNotionPage(args: {
  entityType: string;
  page: NotionPage;
  blocks: NotionBlock[];
  currentContent?: string;
}): NotionImportResult {
  const entityType = entityTypeForModule(args.entityType);
  if (!entityType) {
    return { kind: "remote_deleted", lastEditedTime: args.page.last_edited_time ?? null };
  }
  if (args.page.archived === true || args.page.in_trash === true) {
    return { kind: "remote_deleted", lastEditedTime: args.page.last_edited_time ?? null };
  }
  const properties = args.page.properties ?? {};
  const lastEditedTime = args.page.last_edited_time ?? null;
  const remoteSnapshot: Record<string, unknown> = {
    page_id: args.page.id,
    last_edited_time: lastEditedTime,
  };

  if (entityType !== "inbox_items" && !notionBodyIsLossless(args.blocks)) {
    return {
      kind: "unsupported_content",
      entityType,
      lastEditedTime,
      remoteSnapshot: { ...remoteSnapshot, unsupported_body: true },
    };
  }

  const patch: Record<string, unknown> = {};
  const title = titleText(properties);
  if (entityType === "inbox_items") {
    if (title.length > 0) {
      patch.content = title.slice(0, MAX_TEXT);
    }
    const itemType = selectName(properties.Type);
    if (itemType && INBOX_TYPES.has(itemType)) {
      patch.item_type = itemType;
    }
    const column = selectName(properties.Column);
    if (column && INBOX_COLUMNS.has(column)) {
      patch.inbox_column = column;
    }
    const status = selectName(properties.Status);
    if (status === "done") {
      patch.is_completed = true;
    } else if (status === "open") {
      patch.is_completed = false;
    }
    const pinned = checkboxValue(properties.Pinned);
    if (pinned != null) patch.is_pinned = pinned;
    const archived = checkboxValue(properties.Archived);
    if (archived != null) patch.is_archived = archived;
    const topic = checkboxValue(properties.Topic);
    if (topic != null) patch.is_topic = topic;
  } else {
    if (title.length > 0) {
      patch.title = title.slice(0, MAX_TEXT);
    }
    const imported = flattenLosslessParagraphs(args.blocks);
    const currentParagraphs = notionParagraphsFromContent(args.currentContent ?? "");
    const importedParagraphs = notionParagraphsFromContent(imported);
    if (notionParagraphSequencesEqual(currentParagraphs, importedParagraphs)) {
      if (args.currentContent != null) {
        patch.content = args.currentContent;
      } else {
        patch.content = imported;
      }
    } else {
      patch.content = imported;
    }
    if (entityType === "diary_entries") {
      const entryDate = dateValue(properties.Date);
      if (entryDate) patch.entry_date = entryDate;
      const mood = richTextValue(properties.Mood);
      if (mood != null) patch.mood = mood.length > 0 ? mood : null;
    }
  }

  return {
    kind: "update",
    entityType,
    patch,
    lastEditedTime,
    remoteSnapshot: { ...remoteSnapshot, patch },
  };
}
