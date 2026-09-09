export type OutboundLink = {
  last_synced_revision: number;
  sync_status: string;
  inbound_state?: string;
  entity_id?: string;
  external_id?: string;
  content_hash?: string | null;
};

export function shouldSkipOutbound(
  link: OutboundLink | undefined,
  revision: number,
): boolean {
  if (!link) {
    return false;
  }
  const inbound = link.inbound_state ?? "idle";
  if (inbound === "conflict" || inbound === "error") {
    return true;
  }
  if (inbound === "remote_deleted") {
    return true;
  }
  if (link.sync_status === "skipped") {
    return true;
  }
  return link.sync_status === "synced" && link.last_synced_revision === revision;
}
