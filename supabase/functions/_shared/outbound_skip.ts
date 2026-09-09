export type OutboundLink = {
  last_synced_revision: number;
  sync_status: string;
  inbound_state?: string;
  entity_id?: string;
  external_id?: string;
  content_hash?: string | null;
  outbound_hold?: boolean;
};

export type OutboundDecision = {
  skip: boolean;
  openConflict?: boolean;
  reason?: string;
};

export function decideOutbound(
  link: OutboundLink | undefined,
  revision: number,
  extras?: { connectionDeltaHold?: boolean },
): OutboundDecision {
  if (link?.outbound_hold) {
    return { skip: true, reason: "outbound_hold" };
  }
  if (extras?.connectionDeltaHold) {
    return { skip: true, reason: "inbound_delta_hold" };
  }
  if (!link) {
    return { skip: false };
  }
  const inbound = link.inbound_state ?? "idle";
  if (inbound === "conflict" || inbound === "error") {
    return { skip: true, reason: inbound };
  }
  if (inbound === "remote_deleted") {
    if (revision > link.last_synced_revision) {
      return {
        skip: true,
        openConflict: true,
        reason: "remote_deleted_with_local_edit",
      };
    }
    return { skip: true, reason: "remote_deleted" };
  }
  if (link.sync_status === "skipped") {
    return { skip: true, reason: "skipped" };
  }
  if (link.sync_status === "synced" && link.last_synced_revision === revision) {
    return { skip: true, reason: "unchanged" };
  }
  return { skip: false };
}

export function shouldSkipOutbound(
  link: OutboundLink | undefined,
  revision: number,
  extras?: { connectionDeltaHold?: boolean },
): boolean {
  return decideOutbound(link, revision, extras).skip;
}
