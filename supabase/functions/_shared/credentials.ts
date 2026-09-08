import { db } from "./db.ts";
import {
  decryptTokenBundle,
  encryptTokenBundle,
  type TokenBundle,
} from "./crypto.ts";

function tokenKey(): string {
  const key = Deno.env.get("INTEGRATION_TOKEN_KEY");
  if (!key) {
    throw new Error("INTEGRATION_TOKEN_KEY is not configured");
  }
  return key;
}

export async function writeTokenBundle(
  connectionId: string,
  bundle: TokenBundle,
  accessExpiresAt: Date | null,
): Promise<void> {
  const encrypted = await encryptTokenBundle(bundle, tokenKey());
  await db()`
    insert into integrations.credentials (
      connection_id, token_bundle_cipher, token_bundle_nonce, access_expires_at, token_updated_at
    ) values (
      ${connectionId}, ${encrypted.cipher}, ${encrypted.nonce}, ${accessExpiresAt}, now()
    )
    on conflict (connection_id) do update set
      token_bundle_cipher = excluded.token_bundle_cipher,
      token_bundle_nonce = excluded.token_bundle_nonce,
      access_expires_at = excluded.access_expires_at,
      token_updated_at = excluded.token_updated_at
  `;
}

export type StoredCredential = {
  bundle: TokenBundle;
  accessExpiresAt: Date | null;
};

export async function readCredential(
  connectionId: string,
): Promise<StoredCredential | null> {
  const rows = await db()`
    select token_bundle_cipher, token_bundle_nonce, access_expires_at
    from integrations.credentials
    where connection_id = ${connectionId}
    limit 1
  `;
  if (rows.length === 0) {
    return null;
  }
  const expires = rows[0].access_expires_at;
  return {
    bundle: await decryptTokenBundle(
      {
        cipher: rows[0].token_bundle_cipher as string,
        nonce: rows[0].token_bundle_nonce as Uint8Array,
      },
      tokenKey(),
    ),
    accessExpiresAt: expires ? new Date(expires as string | Date) : null,
  };
}

export async function readTokenBundle(
  connectionId: string,
): Promise<TokenBundle | null> {
  return (await readCredential(connectionId))?.bundle ?? null;
}

export async function deleteCredentials(connectionId: string): Promise<void> {
  await db()`
    delete from integrations.credentials where connection_id = ${connectionId}
  `;
}

export async function insertOauthState(args: {
  state: string;
  userId: string;
  provider: string;
  codeVerifier: string | null;
  returnTo: string | null;
  expiresAt: Date;
}): Promise<void> {
  await db()`
    insert into integrations.oauth_states (
      state, user_id, provider, code_verifier, return_to, expires_at
    ) values (
      ${args.state}, ${args.userId}, ${args.provider}, ${args.codeVerifier},
      ${args.returnTo}, ${args.expiresAt}
    )
  `;
}

export async function consumeOauthState(state: string): Promise<{
  user_id: string;
  provider: string;
  code_verifier: string | null;
  return_to: string | null;
} | null> {
  const rows = await db()`
    delete from integrations.oauth_states
    where state = ${state} and expires_at > now()
    returning user_id, provider, code_verifier, return_to
  `;
  if (rows.length === 0) {
    return null;
  }
  return rows[0] as {
    user_id: string;
    provider: string;
    code_verifier: string | null;
    return_to: string | null;
  };
}
