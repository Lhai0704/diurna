import { db } from "./db.ts";
import { decryptUtf8, encryptUtf8 } from "./crypto.ts";
import {
  generateHandshakeNonce,
  hashHandshakeNonce,
  type HandshakePurpose,
} from "./handshake.ts";

function tokenKey(): string {
  const key = Deno.env.get("INTEGRATION_TOKEN_KEY");
  if (!key) {
    throw new Error("INTEGRATION_TOKEN_KEY is not configured");
  }
  return key;
}

export async function storeNotionVerificationToken(token: string): Promise<void> {
  const encrypted = await encryptUtf8(token, tokenKey());
  await db()`
    insert into integrations.webhook_secrets (
      provider, kind, cipher, nonce, revealed_at, created_at, updated_at
    ) values (
      'notion', 'verification_token', ${encrypted.cipher}, ${encrypted.nonce},
      null, now(), now()
    )
    on conflict (provider, kind) do update set
      cipher = excluded.cipher,
      nonce = excluded.nonce,
      revealed_at = null,
      updated_at = now()
  `;
}

export async function loadNotionVerificationToken(): Promise<string | null> {
  const envToken = Deno.env.get("NOTION_WEBHOOK_SECRET");
  const rows = await db()`
    select cipher, nonce
      from integrations.webhook_secrets
     where provider = 'notion' and kind = 'verification_token'
     limit 1
  `;
  if (rows.length > 0) {
    return decryptUtf8(
      {
        cipher: rows[0].cipher as string,
        nonce: rows[0].nonce as Uint8Array,
      },
      tokenKey(),
    );
  }
  return envToken && envToken.length > 0 ? envToken : null;
}

export async function armNotionHandshake(
  purpose: HandshakePurpose = "initial",
): Promise<{ setupNonce: string; expiresAt: string }> {
  const nonce = generateHandshakeNonce();
  const nonceHash = await hashHandshakeNonce(nonce);
  const expiresAt = new Date(Date.now() + 30 * 60 * 1000);
  await db()`
    insert into integrations.webhook_handshake_arms (
      provider, purpose, nonce_hash, expires_at
    ) values (
      'notion', ${purpose}, ${nonceHash}, ${expiresAt}
    )
  `;
  console.log("notion_handshake_armed");
  return { setupNonce: nonce, expiresAt: expiresAt.toISOString() };
}

export async function acceptNotionHandshake(args: {
  verificationToken: string;
  setupNonce: string | null;
}): Promise<"stored" | "rejected"> {
  if (!args.setupNonce) {
    return "rejected";
  }
  const hasToken = (await loadNotionVerificationToken()) != null;
  const nonceHash = await hashHandshakeNonce(args.setupNonce);
  const consumed = await db()`
    select integrations.consume_handshake_arm(${nonceHash}, ${hasToken}) as result
  `;
  const result = consumed[0]?.result as { result?: string } | undefined;
  if (result?.result !== "ok") {
    return "rejected";
  }
  await storeNotionVerificationToken(args.verificationToken);
  console.log("notion_verification_token_stored");
  return "stored";
}

export async function revealNotionVerificationToken(): Promise<string | null> {
  const sql = db();
  return await sql.begin(async (tx) => {
    const rows = await tx`
      select cipher, nonce, revealed_at
        from integrations.webhook_secrets
       where provider = 'notion' and kind = 'verification_token'
       for update
    `;
    if (rows.length === 0 || rows[0].revealed_at != null) {
      return null;
    }
    const token = await decryptUtf8(
      {
        cipher: rows[0].cipher as string,
        nonce: rows[0].nonce as Uint8Array,
      },
      tokenKey(),
    );
    await tx`
      update integrations.webhook_secrets
         set revealed_at = now(), updated_at = now()
       where provider = 'notion' and kind = 'verification_token'
    `;
    return token;
  });
}
