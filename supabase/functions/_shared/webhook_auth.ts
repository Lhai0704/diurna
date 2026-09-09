const encoder = new TextEncoder();

export function timingSafeEqual(a: string, b: string): boolean {
  const left = encoder.encode(a);
  const right = encoder.encode(b);
  const max = Math.max(left.length, right.length);
  let diff = left.length ^ right.length;
  for (let i = 0; i < max; i++) {
    const x = i < left.length ? left[i] : 0;
    const y = i < right.length ? right[i] : 0;
    diff |= x ^ y;
  }
  return diff === 0;
}

function toHex(bytes: ArrayBuffer): string {
  return [...new Uint8Array(bytes)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

export async function hmacSha256Hex(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(body));
  return toHex(signature);
}

export async function verifyNotionSignature(args: {
  rawBody: string;
  signatureHeader: string | null;
  verificationToken: string;
}): Promise<boolean> {
  const header = args.signatureHeader ?? "";
  if (!header.startsWith("sha256=")) {
    return false;
  }
  const expected = `sha256=${await hmacSha256Hex(args.verificationToken, args.rawBody)}`;
  return timingSafeEqual(expected, header);
}

export function parseNotionVerificationHandshake(
  rawBody: string,
): string | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(rawBody);
  } catch {
    return null;
  }
  if (
    parsed &&
    typeof parsed === "object" &&
    Object.keys(parsed as object).length === 1 &&
    typeof (parsed as { verification_token?: unknown }).verification_token ===
      "string"
  ) {
    const token = (parsed as { verification_token: string }).verification_token;
    return token.length > 0 ? token : null;
  }
  return null;
}

export function maintenanceSecretMatches(
  provided: string | null,
  expected: string,
): boolean {
  if (!provided || !expected) {
    return false;
  }
  return timingSafeEqual(provided, expected);
}
