import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, json } from "../_shared/http.ts";
import { serviceRoleKey, startOauth } from "../_shared/oauth.ts";
import { runSync } from "../_shared/sync.ts";
import { deleteCredentials, readCredential } from "../_shared/credentials.ts";
import { GoogleSession } from "../_shared/google_auth.ts";
import { stopGoogleWatches } from "../_shared/google_watch.ts";
import { settingsInvalidateShortCircuit } from "../_shared/lease_logic.ts";
import { db } from "../_shared/db.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ ok: false, error: { code: "AUTH_REQUIRED" } }, 401);
    }
    const userClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } },
    );
    const token = authHeader.replace(/^Bearer\s+/i, "");
    const { data: userData, error: userError } = await userClient.auth.getUser(token);
    if (userError || !userData.user) {
      return json({ ok: false, error: { code: "AUTH_REQUIRED" } }, 401);
    }
    const userId = userData.user.id;
    const admin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      serviceRoleKey(),
      { auth: { persistSession: false } },
    );
    const body = req.method === "POST" ? await req.json() : {};
    const action = body.action as string;
    const provider = body.provider as "notion" | "google" | undefined;

    if (action === "connect") {
      if (provider !== "notion" && provider !== "google") {
        return json({ ok: false, error: { code: "VALIDATION" } }, 400);
      }
      const authorizationUrl = await startOauth({ userId, provider });
      return json({ ok: true, authorization_url: authorizationUrl });
    }

    if (action === "sync") {
      if (provider !== "notion" && provider !== "google") {
        return json({ ok: false, error: { code: "VALIDATION" } }, 400);
      }
      const result = await runSync({
        userClient,
        admin,
        userId,
        provider,
        runId: typeof body.run_id === "string" ? body.run_id : null,
      });
      const status = result.error && (result.error as { code?: string }).code === "SYNC_IN_PROGRESS"
        ? 409
        : 200;
      return json(result, status);
    }

    if (action === "disconnect") {
      if (provider !== "notion" && provider !== "google") {
        return json({ ok: false, error: { code: "VALIDATION" } }, 400);
      }
      const { data } = await admin
        .from("integration_connections")
        .select("id,sync_lease_until")
        .eq("user_id", userId)
        .eq("provider", provider)
        .maybeSingle();
      if (!data) {
        return json({ ok: true });
      }
      if (data.sync_lease_until && Date.parse(data.sync_lease_until) > Date.now()) {
        return json({ ok: false, error: { code: "SYNC_IN_PROGRESS" } }, 409);
      }
      if (provider === "google") {
        const credential = await readCredential(data.id);
        const session = credential
          ? new GoogleSession(data.id, credential.bundle, credential.accessExpiresAt)
          : null;
        await stopGoogleWatches(data.id, session);
      }
      await admin.from("external_sync_links").delete().eq("connection_id", data.id);
      await deleteCredentials(data.id);
      await admin
        .from("integration_connections")
        .update({
          status: "disconnected",
          inbound_status: "disabled",
          inbound_error: null,
          last_seen_generation: null,
          page_cursor: {},
          sync_run_id: null,
          sync_lease_until: null,
          updated_at: new Date().toISOString(),
        })
        .eq("id", data.id)
        .eq("user_id", userId);
      return json({ ok: true });
    }

    if (action === "update_settings") {
      if (provider !== "notion" && provider !== "google") {
        return json({ ok: false, error: { code: "VALIDATION" } }, 400);
      }
      const sql = db();
      const changed = await sql.begin(async (tx) => {
        const rows = await tx`
          select id, enabled_modules, sync_lease_until
            from public.integration_connections
           where user_id = ${userId}
             and provider = ${provider}
             and status = 'connected'
           for update
        `;
        if (rows.length === 0) {
          return "missing";
        }
        const row = rows[0];
        if (row.sync_lease_until && Date.parse(String(row.sync_lease_until)) > Date.now()) {
          return "busy";
        }
        const nextModules = body.enabled_modules ?? row.enabled_modules;
        const didChange = JSON.stringify(nextModules) !== JSON.stringify(row.enabled_modules);
        if (didChange) {
          const invalidation = settingsInvalidateShortCircuit();
          await tx`
            update public.integration_connections
               set enabled_modules = ${tx.json(nextModules)},
                   last_seen_generation = ${invalidation.last_seen_generation},
                   last_sync_status = ${invalidation.last_sync_status},
                   page_cursor = ${tx.json(invalidation.page_cursor)},
                   sync_start_generation = ${invalidation.sync_start_generation},
                   updated_at = now()
             where id = ${row.id}
               and user_id = ${userId}
          `;
        }
        return didChange ? "changed" : "unchanged";
      });
      if (changed === "missing") {
        return json({ ok: false, error: { code: "NOT_CONNECTED" } }, 404);
      }
      if (changed === "busy") {
        return json({ ok: false, error: { code: "SYNC_IN_PROGRESS" } }, 409);
      }
      return json({ ok: true, changed: changed === "changed" });
    }

    return json({ ok: false, error: { code: "VALIDATION" } }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : "internal";
    if (message.includes("token") || message.includes("Bearer")) {
      console.error("integrations failed");
    } else {
      console.error("integrations failed", message);
    }
    return json({ ok: false, error: { code: "INTERNAL", message: "Request failed" } }, 500);
  }
});
