import { json } from "../_shared/http.ts";
import { loadConnectionRow, setInboundStatus } from "../_shared/connection_status.ts";
import { bootstrapGoogleConnection } from "../_shared/google_bootstrap.ts";
import { bootstrapNotionConnection } from "../_shared/notion_bootstrap.ts";
import { readCredential } from "../_shared/credentials.ts";
import { GoogleSession } from "../_shared/google_auth.ts";
import { renewGoogleWatch } from "../_shared/google_watch.ts";
import {
  processGoogleCalendarGone,
  processGoogleIncrementalWork,
} from "../_shared/google_worker.ts";
import {
  claimInboundWorkOf,
  completeInboundWork,
  deferInboundWork,
  withConnectionInboundLock,
} from "../_shared/inbound_work.ts";
import { runMaintenance, WORK_TYPES } from "../_shared/maintenance.ts";
import { processNotionPageWork } from "../_shared/notion_worker.ts";
import { repairNotionConnection } from "../_shared/notion_repair.ts";
import { maintenanceSecretMatches } from "../_shared/webhook_auth.ts";
import {
  armNotionHandshake,
  revealNotionVerificationToken,
} from "../_shared/webhook_secrets.ts";

function maintenanceAuthorized(req: Request): boolean {
  const expected = Deno.env.get("INTEGRATIONS_MAINTENANCE_SECRET") ?? "";
  const provided = req.headers.get("x-diurna-maintenance");
  return maintenanceSecretMatches(provided, expected);
}

async function processAvailableWork(limit = 20): Promise<number> {
  let processed = 0;
  for (let i = 0; i < limit; i++) {
    const work = await claimInboundWorkOf([...WORK_TYPES]);
    if (!work || typeof work.id !== "string") {
      break;
    }
    const payload = (work.payload ?? {}) as Record<string, unknown>;
    const connectionId = String(work.connection_id ?? "");
    const workType = String(work.work_type ?? "");
    try {
      const outcome = await withConnectionInboundLock(connectionId, async () => {
        if (workType === "notion_page") {
          return await processNotionPageWork({
            connectionId,
            pageId: String(payload.page_id ?? work.dedup_key ?? ""),
            eventType: String(payload.event_type ?? "page.properties_updated"),
          });
        }
        if (workType === "google_incremental") {
          return await processGoogleIncrementalWork({ connectionId });
        }
        if (workType === "google_calendar_gone") {
          return await processGoogleCalendarGone(connectionId);
        }
        if (workType === "bootstrap_google") {
          return await bootstrapGoogleConnection({ connectionId });
        }
        if (workType === "bootstrap_notion") {
          return await bootstrapNotionConnection({ connectionId });
        }
        if (workType === "renew_watch") {
          const credential = await readCredential(connectionId);
          if (!credential) {
            throw new Error("REAUTH_REQUIRED");
          }
          const session = new GoogleSession(
            connectionId,
            credential.bundle,
            credential.accessExpiresAt,
          );
          const connection = await loadConnectionRow(connectionId);
          const calendarId =
            ((connection?.container as { calendar_id?: string } | undefined)?.calendar_id) ??
            null;
          const renewed = await renewGoogleWatch({ connectionId, session, calendarId });
          if (renewed.renewed) {
            await setInboundStatus(connectionId, "watch_ok", { result: "renew_watch" });
          }
          return { result: renewed.renewed ? "ok" : (renewed.skipped ?? "ok") };
        }
        if (workType === "repair") {
          return await repairNotionConnection({ connectionId });
        }
        return { result: "ok" };
      });
      if (outcome.result === "deferred") {
        await deferInboundWork(work.id);
        processed += 1;
        continue;
      }
      await completeInboundWork(work.id, null);
      processed += 1;
    } catch (error) {
      const message = error instanceof Error ? error.message : "worker_failed";
      if (message.includes("REAUTH_REQUIRED")) {
        await setInboundStatus(connectionId, "reauth", { error: "REAUTH_REQUIRED" });
      }
      if (message.includes("token") || message.includes("Bearer")) {
        console.error("inbound worker failed");
      } else {
        console.error("inbound worker failed", message);
      }
      await completeInboundWork(work.id, message);
    }
  }
  return processed;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return json({ ok: true });
  }
  if (req.method !== "POST") {
    return json({ ok: false }, 405);
  }
  if (!maintenanceAuthorized(req)) {
    return json({ ok: false, error: "AUTH_REQUIRED" }, 401);
  }
  let body: { action?: string; purpose?: string } = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  try {
    if (body.action === "reveal_notion_verification_token") {
      const token = await revealNotionVerificationToken();
      if (!token) {
        return json({ ok: false, error: "NOT_FOUND" }, 404);
      }
      return json({ ok: true, verification_token: token });
    }
    if (body.action === "arm_notion_handshake") {
      const purpose = body.purpose === "rotate" ? "rotate" : "initial";
      const armed = await armNotionHandshake(purpose);
      return json({
        ok: true,
        setup_nonce: armed.setupNonce,
        expires_at: armed.expiresAt,
      });
    }
    const maintenance = await runMaintenance();
    const processed = await processAvailableWork();
    return json({ ok: true, processed, maintenance });
  } catch (error) {
    const message = error instanceof Error ? error.message : "internal";
    if (message.includes("token") || message.includes("secret")) {
      console.error("inbound worker failed");
    } else {
      console.error("inbound worker failed", message);
    }
    return json({ ok: false }, 500);
  }
});
