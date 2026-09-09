/** Canonical Memo/Diary Notion paragraph semantics. Import and export share this. */

export const MAX_NOTION_PARAGRAPHS = 100;
export const MAX_NOTION_TEXT = 2000;

/** CRLF and lone CR become LF. Do not trim or collapse other whitespace. */
export function normalizeNotionLineEndings(value: string): string {
  return value.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
}

/**
 * Paragraph sequence used for Notion Memo/Diary bodies.
 * Runs of newlines delimit paragraphs. A trailing newline yields a trailing
 * empty paragraph. Empty input is no paragraphs. Max 100 paragraphs.
 */
export function notionParagraphsFromContent(content: string): string[] {
  if (!content) {
    return [];
  }
  return normalizeNotionLineEndings(content).split(/\n+/).slice(0, MAX_NOTION_PARAGRAPHS);
}

export function notionParagraphSequencesEqual(
  left: string[],
  right: string[],
): boolean {
  return left.length === right.length && left.every((line, i) => line === right[i]);
}
