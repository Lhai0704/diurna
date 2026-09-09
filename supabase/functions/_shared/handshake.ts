export type HandshakePurpose = "initial" | "rotate";

export type HandshakeArm = {
  purpose: HandshakePurpose;
  nonceHash: string;
  expiresAt: Date;
  consumedAt: Date | null;
};

export function handshakeDecision(args: {
  hasActiveToken: boolean;
  arm: HandshakeArm | null;
  now?: Date;
}): "store" | "reject" {
  const now = args.now ?? new Date();
  if (!args.arm) {
    return "reject";
  }
  if (args.arm.consumedAt != null) {
    return "reject";
  }
  if (args.arm.expiresAt.getTime() <= now.getTime()) {
    return "reject";
  }
  if (args.hasActiveToken && args.arm.purpose !== "rotate") {
    return "reject";
  }
  return "store";
}

export function generateHandshakeNonce(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return [...bytes].map((value) => value.toString(16).padStart(2, "0")).join("");
}

export async function hashHandshakeNonce(nonce: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(nonce),
  );
  return [...new Uint8Array(digest)]
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}
