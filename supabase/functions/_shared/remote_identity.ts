/** Provider IDs may use compact UUIDs; Diurna metadata must be a real UUID. */
export function diurnaId(value: unknown): string | null {
  return typeof value === "string" &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        value,
      )
    ? value.toLowerCase()
    : null;
}

export function notionId(value: string): string {
  const compact = value.replaceAll("-", "").toLowerCase();
  return /^[0-9a-f]{32}$/.test(compact)
    ? `${compact.slice(0, 8)}-${compact.slice(8, 12)}-${
      compact.slice(12, 16)
    }-${compact.slice(16, 20)}-${compact.slice(20)}`
    : value;
}

export function validDate(value: unknown): value is string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }
  const parsed = new Date(value);
  return Number.isFinite(parsed.getTime()) &&
    parsed.toISOString().slice(0, 10) === value;
}
