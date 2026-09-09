export type InboundDecision =
  | "applied"
  | "duplicate"
  | "stale"
  | "conflict"
  | "remote_deleted"
  | "ignored"
  | "error";

export type ProviderClock = {
  etag?: string | null;
  storedEtag?: string | null;
  incomingUpdated?: Date | null;
  storedUpdated?: Date | null;
  provider?: "notion" | "google";
};

export function decideProviderVersion(args: {
  provider: "notion" | "google";
  etag?: string | null;
  storedEtag?: string | null;
  incomingUpdated?: Date | null;
  storedUpdated?: Date | null;
  mappedEqual: boolean;
}): "duplicate" | "stale" | "continue" {
  if (
    args.provider === "google" &&
    args.etag != null &&
    args.storedEtag != null &&
    args.etag === args.storedEtag
  ) {
    return "duplicate";
  }
  if (args.incomingUpdated != null && args.storedUpdated != null) {
    if (args.incomingUpdated.getTime() < args.storedUpdated.getTime()) {
      return "stale";
    }
    if (
      args.incomingUpdated.getTime() === args.storedUpdated.getTime() &&
      args.mappedEqual
    ) {
      return "duplicate";
    }
  }
  return "continue";
}

export function decideRevision(args: {
  revision: number;
  lastSyncedRevision: number;
  inboundState: string;
  operation: "update" | "remote_deleted";
  mappedEqual: boolean;
}): InboundDecision {
  if (args.inboundState === "conflict") {
    return "conflict";
  }
  if (args.operation === "remote_deleted") {
    if (args.revision > args.lastSyncedRevision) {
      return "conflict";
    }
    return "remote_deleted";
  }
  if (args.inboundState === "remote_deleted") {
    return args.revision > args.lastSyncedRevision ? "conflict" : "ignored";
  }
  if (args.revision < args.lastSyncedRevision) {
    return "error";
  }
  if (args.revision > args.lastSyncedRevision) {
    return "conflict";
  }
  if (args.mappedEqual) {
    return "duplicate";
  }
  return "applied";
}
