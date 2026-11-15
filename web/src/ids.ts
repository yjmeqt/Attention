const base62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

/** 10 random base62 characters, about 59 bits: unguessable and not enumerable. */
export function newListID(length = 10): string {
  let id = "";
  while (id.length < length) {
    for (const byte of crypto.getRandomValues(new Uint8Array(length * 2))) {
      // 248 = 4 × 62; rejecting the rest keeps every character equally likely.
      if (byte < 248 && id.length < length) id += base62[byte % 62];
    }
  }
  return id;
}

export const listIDPattern = /^[0-9A-Za-z]{10}$/;

/** 32 random bytes, base64url. Only the app keeps it; the server stores its hash. */
export function newDeleteToken(): string {
  return base64url(crypto.getRandomValues(new Uint8Array(32)));
}

export async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return base64url(new Uint8Array(digest));
}

/** Compares two hashes without returning early at the first difference. */
export function sameHash(a: string, b: string): boolean {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  if (left.length !== right.length) return false;
  return crypto.subtle.timingSafeEqual(left, right);
}

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}
