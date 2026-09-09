export function patchMatchesRow(
  row: Record<string, unknown>,
  patch: Record<string, unknown>,
): boolean {
  for (const [key, value] of Object.entries(patch)) {
    const current = row[key];
    if (value == null) {
      if (current != null && current !== "") {
        return false;
      }
      continue;
    }
    if (typeof value === "boolean") {
      if (Boolean(current) !== value) {
        return false;
      }
      continue;
    }
    if (String(current ?? "") !== String(value)) {
      return false;
    }
  }
  return true;
}

export const RENEW_SAFETY_MS = 36 * 60 * 60 * 1000;
export const REPAIR_INTERVAL_MS = 15 * 60 * 1000;
export const INBOUND_EVENT_TTL_HOURS = 48;
export const RETIRING_RETRY_MS = 60 * 60 * 1000;
export const DEFER_BOOTSTRAP_SECONDS = 120;

export function shouldRenewWatch(args: {
  now: Date;
  expiresAt: string | null | undefined;
  status: string;
  hasCreating: boolean;
}): boolean {
  if (args.hasCreating) {
    return false;
  }
  if (args.status !== "active") {
    return false;
  }
  if (args.expiresAt == null || args.expiresAt === "") {
    return false;
  }
  const expires = Date.parse(args.expiresAt);
  if (!Number.isFinite(expires)) {
    return false;
  }
  return expires < args.now.getTime() + RENEW_SAFETY_MS;
}

export function shouldEnqueueRepair(args: {
  now: Date;
  lastInboundAt: string | null | undefined;
  inboundStatus: string;
  hasRepairState?: boolean;
}): boolean {
  if (args.inboundStatus !== "active" && args.inboundStatus !== "degraded") {
    return false;
  }
  if (args.hasRepairState) {
    return true;
  }
  if (args.lastInboundAt == null) {
    return true;
  }
  const last = Date.parse(args.lastInboundAt);
  if (!Number.isFinite(last)) {
    return true;
  }
  return args.now.getTime() - last >= REPAIR_INTERVAL_MS;
}

export type InboundStatus =
  | "disabled"
  | "bootstrapping"
  | "active"
  | "degraded"
  | "error";

export type InboundStatusEvent =
  | "bootstrap_start"
  | "bootstrap_ok_watch_ok"
  | "bootstrap_ok_watch_failed"
  | "watch_failed"
  | "watch_ok"
  | "transient_fail"
  | "transient_ok"
  | "reauth"
  | "calendar_gone"
  | "disconnect";

export function nextInboundStatus(
  current: InboundStatus,
  event: InboundStatusEvent,
): InboundStatus {
  if (event === "disconnect") {
    return "disabled";
  }
  if (event === "reauth" || event === "calendar_gone") {
    return "error";
  }
  if (current === "error") {
    return "error";
  }
  if (event === "bootstrap_start") {
    return "bootstrapping";
  }
  if (event === "bootstrap_ok_watch_ok" || event === "watch_ok" || event === "transient_ok") {
    if (current === "bootstrapping" || current === "degraded" || current === "active") {
      return "active";
    }
  }
  if (event === "bootstrap_ok_watch_failed" || event === "watch_failed" || event === "transient_fail") {
    if (current === "bootstrapping" || current === "active" || current === "degraded") {
      return "degraded";
    }
  }
  return current;
}
