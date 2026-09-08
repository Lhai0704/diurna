import { appOrigin, finishOauth } from "../_shared/oauth.ts";
import { redirect } from "../_shared/http.ts";

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const origin = appOrigin();
  const error = url.searchParams.get("error");
  const state = url.searchParams.get("state");
  const code = url.searchParams.get("code");
  if (error || !state || !code) {
    return redirect(
      `${origin}/integrations/connected?error=${encodeURIComponent(error || "access_denied")}`,
    );
  }
  try {
    const finished = await finishOauth({ code, state });
    return redirect(
      `${finished.returnTo || origin}/integrations/connected?provider=${encodeURIComponent(finished.provider)}`,
    );
  } catch {
    return redirect(`${origin}/integrations/connected?error=oauth_failed`);
  }
});
