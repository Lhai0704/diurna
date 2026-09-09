import { db } from "./db.ts";
import { type InboundStatus, type InboundStatusEvent, nextInboundStatus } from "./mapped.ts";

export async function loadConnectionRow(
  connectionId: string,
): Promise<Record<string, unknown> | null> {
  const rows = await db()`
    select id, user_id, status, provider, container, inbound_status,
           last_inbound_at, last_inbound_result, inbound_error
      from public.integration_connections
     where id = ${connectionId}::uuid
     limit 1
  `;
  return (rows[0] as Record<string, unknown> | undefined) ?? null;
}

export async function setInboundStatus(
  connectionId: string,
  event: InboundStatusEvent,
  extra?: { error?: string | null; result?: string | null },
): Promise<InboundStatus> {
  const row = await loadConnectionRow(connectionId);
  const current = (row?.inbound_status as InboundStatus | undefined) ?? "disabled";
  const next = nextInboundStatus(current, event);
  const error = extra && "error" in extra ? extra.error ?? null : (row?.inbound_error as string | null) ?? null;
  const result = extra?.result ?? (row?.last_inbound_result as string | null) ?? null;
  if (extra?.result) {
    await db()`
      update public.integration_connections
         set inbound_status = ${next},
             inbound_error = ${error},
             last_inbound_result = ${result},
             last_inbound_at = now(),
             updated_at = now()
       where id = ${connectionId}::uuid
    `;
  } else {
    await db()`
      update public.integration_connections
         set inbound_status = ${next},
             inbound_error = ${error},
             updated_at = now()
       where id = ${connectionId}::uuid
    `;
  }
  return next;
}

export async function touchInboundOk(connectionId: string, result = "ok"): Promise<void> {
  await db()`
    update public.integration_connections
       set last_inbound_at = now(),
           last_inbound_result = ${result},
           inbound_error = null,
           updated_at = now()
     where id = ${connectionId}::uuid
       and status = 'connected'
  `;
}
