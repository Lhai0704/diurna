import { json } from "../_shared/http.ts";
import { acceptInboundEvent, recordInboundEvent } from "../_shared/inbound_work.ts";
import { handleGoogleWebhook } from "../_shared/google_webhook.ts";
import { lookupWatchByChannelId } from "../_shared/google_watch.ts";

Deno.serve(async (req) => {
  try {
    return await handleGoogleWebhook(req, {
      lookupWatch: lookupWatchByChannelId,
      acceptWork: async (args) => {
        const result = await acceptInboundEvent({
          provider: "google",
          eventKey: args.eventKey,
          connectionId: args.connectionId,
          workType: args.workType,
          dedupKey: args.connectionId,
          payload: { work_type: args.workType },
        });
        return { accepted: result.accepted, duplicate: result.duplicate };
      },
      recordSync: async (args) => {
        await recordInboundEvent({
          provider: "google",
          eventKey: args.eventKey,
          connectionId: args.connectionId,
          result: "sync",
        });
      },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "internal";
    if (
      message.includes("token") ||
      message.includes("secret") ||
      message.includes("cipher")
    ) {
      console.error("google webhook failed");
    } else {
      console.error("google webhook failed", message);
    }
    return json({ ok: false }, 500);
  }
});
