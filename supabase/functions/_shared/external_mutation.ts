import { db } from "./db.ts";

export type ApplyOperation = "update" | "remote_deleted";

export type ApplyResult = {
  result: string;
  reason?: string;
  revision_before?: number;
  revision_after?: number;
  last_synced_revision?: number;
  generation_after?: number;
};

export async function applyExternalChange(args: {
  connectionId: string;
  entityType: string;
  entityId: string;
  externalId: string;
  operation: ApplyOperation;
  patch: Record<string, unknown>;
  remoteSnapshot?: Record<string, unknown>;
  providerEtag?: string | null;
  providerUpdatedAt?: string | null;
}): Promise<ApplyResult> {
  const sql = db();
  const rows = await sql`
    select integrations.apply_external_change(
      ${args.connectionId}::uuid,
      ${args.entityType},
      ${args.entityId}::uuid,
      ${args.externalId},
      ${args.operation},
      ${sql.json(JSON.parse(JSON.stringify(args.patch)))}::jsonb,
      ${sql.json(JSON.parse(JSON.stringify(args.remoteSnapshot ?? {})))}::jsonb,
      ${args.providerEtag ?? null},
      ${args.providerUpdatedAt ?? null}::timestamptz
    ) as result
  `;
  return rows[0].result as ApplyResult;
}

export async function bootstrapLinkVersion(args: {
  connectionId: string;
  entityType: string;
  entityId: string;
  externalId: string;
  providerEtag?: string | null;
  providerUpdatedAt?: string | null;
  drift: boolean;
  reason?: string;
  localSnapshot?: Record<string, unknown>;
  remoteSnapshot?: Record<string, unknown>;
}): Promise<ApplyResult> {
  const sql = db();
  const rows = await sql`
    select integrations.bootstrap_link_version(
      ${args.connectionId}::uuid,
      ${args.entityType},
      ${args.entityId}::uuid,
      ${args.externalId},
      ${args.providerEtag ?? null},
      ${args.providerUpdatedAt ?? null}::timestamptz,
      ${args.drift},
      ${args.reason ?? "bootstrap_remote_drift"},
      ${sql.json(JSON.parse(JSON.stringify(args.localSnapshot ?? {})))}::jsonb,
      ${sql.json(JSON.parse(JSON.stringify(args.remoteSnapshot ?? {})))}::jsonb
    ) as result
  `;
  return rows[0].result as ApplyResult;
}

export async function freezeLinkConflict(args: {
  connectionId: string;
  entityType: string;
  entityId: string;
  externalId: string;
  reason: string;
  remoteSnapshot?: Record<string, unknown>;
  providerEtag?: string | null;
  providerUpdatedAt?: string | null;
}): Promise<ApplyResult> {
  const sql = db();
  const rows = await sql`
    select integrations.freeze_link_conflict(
      ${args.connectionId}::uuid,
      ${args.entityType},
      ${args.entityId}::uuid,
      ${args.externalId},
      ${args.reason},
      ${sql.json(JSON.parse(JSON.stringify(args.remoteSnapshot ?? {})))}::jsonb,
      ${args.providerEtag ?? null},
      ${args.providerUpdatedAt ?? null}::timestamptz
    ) as result
  `;
  return rows[0].result as ApplyResult;
}

export async function restoreRemoteDeletedLink(args: {
  connectionId: string;
  entityType: string;
  entityId: string;
  externalId: string;
}): Promise<ApplyResult> {
  const rows = await db()`
    select integrations.restore_remote_deleted_link(
      ${args.connectionId}::uuid,
      ${args.entityType},
      ${args.entityId}::uuid,
      ${args.externalId}
    ) as result
  `;
  return rows[0].result as ApplyResult;
}
