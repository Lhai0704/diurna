import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  notionParagraphsFromContent,
  notionParagraphSequencesEqual,
  normalizeNotionLineEndings,
} from "./notion_text.ts";

Deno.test("normalize CRLF, lone CR, and mixed line endings to LF", () => {
  assertEquals(normalizeNotionLineEndings("a\r\nb"), "a\nb");
  assertEquals(normalizeNotionLineEndings("a\rb"), "a\nb");
  assertEquals(normalizeNotionLineEndings("a\r\nb\nc\rd"), "a\nb\nc\nd");
});

Deno.test("paragraphs: LF, CRLF, lone CR, and mixed encodings match", () => {
  const lf = notionParagraphsFromContent("a\nb\n");
  const crlf = notionParagraphsFromContent("a\r\nb\r\n");
  const cr = notionParagraphsFromContent("a\rb\r");
  const mixed = notionParagraphsFromContent("a\r\nb\n");
  assertEquals(lf, ["a", "b", ""]);
  assertEquals(crlf, lf);
  assertEquals(cr, lf);
  assertEquals(mixed, lf);
  assertEquals(notionParagraphSequencesEqual(lf, crlf), true);
});

Deno.test("trailing newline yields trailing empty paragraph; empty input is none", () => {
  assertEquals(notionParagraphsFromContent(""), []);
  assertEquals(notionParagraphsFromContent("a\n"), ["a", ""]);
  assertEquals(notionParagraphsFromContent("a\r\n"), ["a", ""]);
});

Deno.test("runs of newlines delimit without trimming meaningful spaces", () => {
  assertEquals(notionParagraphsFromContent("  a  \n\n  b  "), ["  a  ", "  b  "]);
  assertEquals(notionParagraphsFromContent("a\n\n\nb"), ["a", "b"]);
  assertEquals(
    notionParagraphSequencesEqual(
      notionParagraphsFromContent("a "),
      notionParagraphsFromContent("a"),
    ),
    false,
  );
});

Deno.test("paragraph cap is 100", () => {
  const content = Array.from({ length: 120 }, (_, i) => `p${i}`).join("\n");
  assertEquals(notionParagraphsFromContent(content).length, 100);
});
