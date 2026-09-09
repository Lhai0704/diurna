import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  mergeRepairState,
  shouldAdvanceRepairWatermark,
} from "./notion_repair.ts";

Deno.test("bounded repair does not advance watermark while has_more remains", () => {
  let state = mergeRepairState({
    previous: {},
    sourceId: "memo_ds",
    sinceIso: "2026-09-09T00:00:00.000Z",
    hasMore: true,
    nextCursor: "cursor-3",
  });
  assertEquals(shouldAdvanceRepairWatermark(state), false);
  assertEquals(state.memo_ds?.cursor, "cursor-3");
  state = mergeRepairState({
    previous: state,
    sourceId: "memo_ds",
    sinceIso: "2026-09-09T00:00:00.000Z",
    hasMore: false,
    nextCursor: null,
  });
  assertEquals(shouldAdvanceRepairWatermark(state), true);
});

Deno.test("more than 300 changed pages keep a continuation cursor", () => {
  const first300 = mergeRepairState({
    previous: {},
    sourceId: "inbox_ds",
    sinceIso: "2026-09-09T00:00:00.000Z",
    hasMore: true,
    nextCursor: "page-4",
  });
  assertEquals(first300.inbox_ds?.cursor, "page-4");
  assertEquals(shouldAdvanceRepairWatermark(first300), false);
});
