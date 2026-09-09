import { db } from "./db.ts";
import { decryptUtf8, encryptUtf8 } from "./crypto.ts";

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
