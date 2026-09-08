const encoder = new TextEncoder();
const decoder = new TextDecoder();

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) {
    binary += String.fromCharCode(b);
  }
  return btoa(binary);
}

function base64ToBytes(value: string): Uint8Array<ArrayBuffer> {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function asIv(bytes: Uint8Array): Uint8Array<ArrayBuffer> {
  return new Uint8Array(bytes);
}

async function importKey(secret: string): Promise<CryptoKey> {
  const hash = await crypto.subtle.digest("SHA-256", encoder.encode(secret));
  return crypto.subtle.importKey("raw", hash, "AES-GCM", false, [
    "encrypt",
    "decrypt",
  ]);
}

export type TokenBundle = {
  access_token: string;
  refresh_token: string;
};

export type EncryptedBundle = {
  cipher: string;
  nonce: Uint8Array;
};

export async function encryptTokenBundle(
  bundle: TokenBundle,
  secret: string,
): Promise<EncryptedBundle> {
  const key = await importKey(secret);
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const plaintext = encoder.encode(JSON.stringify(bundle));
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: "AES-GCM", iv: asIv(nonce) },
      key,
      plaintext,
    ),
  );
  return { cipher: bytesToBase64(ciphertext), nonce };
}

export async function decryptTokenBundle(
  encrypted: EncryptedBundle,
  secret: string,
): Promise<TokenBundle> {
  const key = await importKey(secret);
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: asIv(encrypted.nonce) },
    key,
    asIv(base64ToBytes(encrypted.cipher)),
  );
  const parsed = JSON.parse(decoder.decode(plaintext)) as TokenBundle;
  if (
    typeof parsed.access_token !== "string" ||
    typeof parsed.refresh_token !== "string"
  ) {
    throw new Error("invalid token bundle");
  }
  return parsed;
}
