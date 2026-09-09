import { json } from "../_shared/http.ts";
import { db } from "../_shared/db.ts";
import { acceptInboundEvent } from "../_shared/inbound_work.ts";
import { handleNotionWebhook } from "../_shared/notion_webhook.ts";
import {
  loadNotionVerificationToken,
  storeNotionVerificationToken,
} from "../_shared/webhook_secrets.ts";

async function lookupConnectionIds(args: {
  workspaceId: string | null;
  pageId: string | null;
}): Promise<string[]> {
  const sql = db();
  const ids = new Set<string>();
  if (args.pageId) {
    const linked = await sql`
      select distinct l.connection_id::text as id
        from public.external_sync_links l
        join public.integration_connections c on c.id = l.connection_id
       where l.provider = 'notion'
         and l.external_id = ${args.pageId}
         and c.status = 'connected'
    `;
    for (const row of linked) {
      ids.add(String(row.id));
    }
  }
  if (ids.size === 0 && args.workspaceId) {
    const rows = await sql`
      select id::text as id
        from public.integration_connections
       where provider = 'notion'
         and status = 'connected'
         and provider_account_id = ${args.workspaceId}
    `;
    for (const row of rows) {
      ids.add(String(row.id));
    }
  }
  return [...ids];
}

Deno.serve(async (req) => {
  try {
    return await handleNotionWebhook(req, {
      loadVerificationToken: loadNotionVerificationToken,
      storeVerificationToken: storeNotionVerificationToken,
      lookupConnectionIds,
      acceptEvent: async (args) => {
        const result = await acceptInboundEvent({
          provider: "notion",
          eventKey: args.eventKey,
          connectionId: args.connectionId,
          workType: "notion_page",
          dedupKey: args.pageId,
          payload: {
            page_id: args.pageId,
            event_type: args.eventType,
            workspace_id: args.workspaceId,
          },
        });
        return { accepted: result.accepted, duplicate: result.duplicate };
      },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "internal";
    if (
      message.includes("token") ||
      message.includes("secret") ||
      message.includes("cipher")
    ) {
      console.error("notion webhook failed");
    } else {
      console.error("notion webhook failed", message);
    }
    return json({ ok: false }, 500);
  }
});
