import { db } from "./db.ts";
import { diurnaId } from "./remote_identity.ts";

export type ReconcileResult = {
  result: string;
  reason?: string;
  entity_id?: string;
  revision?: number;
};
export type ReconcileInput = {
  connectionId: string;
  provider: "notion" | "google";
  containerId: string;
  entityType: string;
  externalId: string;
  candidateId: unknown;
  patch: Record<string, unknown>;
  remoteSnapshot: Record<string, unknown>;
  providerEtag?: string | null;
  providerUpdatedAt?: string | null;
  unsupportedReason?: "unsupported_content";
};

export async function reconcileExternalObject(
  args: ReconcileInput,
): Promise<ReconcileResult> {
  const sql = db();
  const rows = await sql`select integrations.reconcile_external_object(
    ${args.connectionId}::uuid, ${args.provider}, ${args.containerId}, ${args.entityType},
    ${args.externalId}, ${diurnaId(args.candidateId)}::uuid,
    ${sql.json(JSON.parse(JSON.stringify(args.patch)))}::jsonb,
    ${sql.json(JSON.parse(JSON.stringify(args.remoteSnapshot)))}::jsonb,
    ${args.providerEtag ?? null}, ${
    args.providerUpdatedAt ?? null
  }::timestamptz, ${args.unsupportedReason ?? null}
  ) as result`;
  const result = rows[0].result as ReconcileResult;
  await recordRemoteReason(
    args.connectionId,
    args.externalId,
    result.reason ?? null,
  );
  return result;
}

export async function recordRemoteReason(
  connectionId: string,
  externalId: string,
  reason: string | null,
): Promise<void> {
  await db()`insert into integrations.remote_object_status(connection_id,external_id,reason)
    values(${connectionId}::uuid,${externalId},${reason})
    on conflict(connection_id,external_id) do update set reason=excluded.reason,updated_at=now()`;
}
