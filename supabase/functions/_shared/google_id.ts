const UUID_DASH = /-/g;

/** Google event ids allow base32hex [0-9a-v]. UUID hex is 0-9a-f. */
export function googleEventId(entityId: string): string {
  return `durna${entityId.replace(UUID_DASH, "").toLowerCase()}`;
}
