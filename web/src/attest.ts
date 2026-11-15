/**
 App Attest: uploads prove they come from a genuine copy of Attention on a real Apple device.
 https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server

 1. The app makes a key in the Secure Enclave and asks Apple to attest it, over a challenge from
    GET /api/attest/challenge. It sends the attestation to POST /api/attest, which checks it here and keeps
    the key's public key (R2 `attest/<key id>`).
 2. Each upload carries an assertion from that key over a fresh challenge and the list's JSON
    (`X-Attest-Key`, `X-Attest-Challenge`, `X-Attest-Assertion`). Its counter must go up each time.

 ATTEST_MODE decides what a missing or bad assertion does: "require" refuses the upload, "log" only
 records it (simulators can't attest, and older builds don't try), "off" skips the check.
*/

import { decodeCBOR, field, InvalidCBOR } from "./cbor";
import { certificate, children, InvalidDER, parse, pemBody, rawSignature, type Certificate } from "./der";

/** The apps allowed to attest: team ID and bundle ID, Release and Debug. */
export const appIDs = ["M3V5P234X3.com.yjmeqt.attn", "M3V5P234X3.com.yjmeqt.attn.dev"];

const nonceExtension = "1.2.840.113635.100.8.2";
const aaguids: Record<string, "production" | "development"> = {
  "appattest\0\0\0\0\0\0\0": "production",
  appattestdevelop: "development",
};

export class AttestError extends Error {}

function fail(message: string): never {
  throw new AttestError(message);
}

export type AttestedKey = {
  keyID: string;
  /** SubjectPublicKeyInfo, base64. */
  spki: string;
  counter: number;
  appID: string;
  environment: "production" | "development";
  createdAt: string;
};

export async function sha256(...parts: Uint8Array[]): Promise<Uint8Array> {
  const joined = new Uint8Array(parts.reduce((sum, part) => sum + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    joined.set(part, offset);
    offset += part.length;
  }
  return new Uint8Array(await crypto.subtle.digest("SHA-256", joined));
}

function equal(a: Uint8Array, b: Uint8Array): boolean {
  return a.length === b.length && a.every((byte, index) => byte === b[index]);
}

export function base64(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes));
}

export function fromBase64(text: string): Uint8Array {
  try {
    return Uint8Array.from(atob(text.replaceAll("-", "+").replaceAll("_", "/")), (char) => char.charCodeAt(0));
  } catch {
    fail("not base64");
  }
}

async function verifySignature(signer: Certificate | { spki: Uint8Array; curve: Certificate["curve"] },
                               hash: "SHA-256" | "SHA-384", signature: Uint8Array, data: Uint8Array): Promise<boolean> {
  const key = await crypto.subtle.importKey("spki", signer.spki, { name: "ECDSA", namedCurve: signer.curve.name }, false, ["verify"]);
  return crypto.subtle.verify({ name: "ECDSA", hash }, key, rawSignature(signature, signer.curve.size), data);
}

/** Authenticator data: the RP ID hash, flags, counter and, in an attestation, the attested key. */
function authenticatorData(bytes: Uint8Array, attested: boolean) {
  const tooShort = () => fail(`authenticator data too short (${bytes.length} bytes, flags ${bytes[32]?.toString(16) ?? "none"})`);
  if (bytes.length < 37) tooShort();
  const counter = new DataView(bytes.buffer, bytes.byteOffset + 33, 4).getUint32(0);
  const result = { rpIDHash: bytes.subarray(0, 32), counter, aaguid: undefined as Uint8Array | undefined, credentialID: undefined as Uint8Array | undefined };
  // An attestation's carries the attested key's AAGUID and credential ID after that; an assertion's doesn't.
  if (attested) {
    if (bytes.length < 55) tooShort();
    result.aaguid = bytes.subarray(37, 53);
    const idLength = (bytes[53]! << 8) | bytes[54]!;
    if (bytes.length < 55 + idLength) tooShort();
    result.credentialID = bytes.subarray(55, 55 + idLength);
  }
  return result;
}

async function matchingAppID(rpIDHash: Uint8Array): Promise<string> {
  for (const appID of appIDs) {
    if (equal(rpIDHash, await sha256(new TextEncoder().encode(appID)))) return appID;
  }
  fail("not one of our apps");
}

/**
 Checks an attestation object for `keyID` over `clientDataHash` (the SHA-256 of the challenge), following
 Apple's steps, and returns the key to keep. `rootPEM` is Apple's App Attestation root (src/appAttestRoot.ts).
*/
export async function verifyAttestation(input: {
  attestation: Uint8Array;
  keyID: Uint8Array;
  clientDataHash: Uint8Array;
  rootPEM: string;
  now: Date;
}): Promise<AttestedKey> {
  try {
    const object = decodeCBOR(input.attestation);
    if (field(object, "fmt") !== "apple-appattest") fail("not an App Attest attestation");
    const statement = field(object, "attStmt");
    const chain = field(statement ?? null, "x5c");
    const authData = field(object, "authData");
    if (!Array.isArray(chain) || chain.length < 2 || !(authData instanceof Uint8Array)) fail("missing fields");
    if (!chain.every((item) => item instanceof Uint8Array)) fail("bad certificate chain");

    // 1. The chain: the credential certificate, the intermediate, then Apple's root.
    const [leaf, intermediate] = (chain as Uint8Array[]).map(certificate);
    const root = certificate(pemBody(input.rootPEM));
    for (const [subject, issuer] of [[leaf!, intermediate!], [intermediate!, root]] as const) {
      if (input.now < subject.notBefore || input.now > subject.notAfter) fail("certificate outside its validity");
      if (!(await verifySignature(issuer, subject.signatureHash, subject.signature, subject.tbs))) fail("bad certificate signature");
    }

    // 2–4. The nonce in the credential certificate binds it to this authenticator data and challenge.
    const nonce = await sha256(authData, input.clientDataHash);
    const extension = leaf!.extensions.get(nonceExtension) ?? fail("no nonce extension");
    const [tagged] = children(parse(extension));
    const [octets] = children(tagged ?? fail("bad nonce extension"));
    if (!octets || octets.tag !== 0x04 || !equal(octets.content, nonce)) fail("nonce doesn't match");

    // 5. The key ID is the SHA-256 of the public key.
    if (!equal(await sha256(leaf!.publicKey), input.keyID)) fail("key ID doesn't match the certificate");

    // 6–9. Our app, a fresh counter, an App Attest environment, and the same key ID.
    const data = authenticatorData(authData, true);
    const appID = await matchingAppID(data.rpIDHash);
    if (data.counter !== 0) fail("counter isn't zero");
    const environment = data.aaguid && aaguids[new TextDecoder().decode(data.aaguid)];
    if (!environment) fail("unknown App Attest environment");
    if (!data.credentialID || !equal(data.credentialID, input.keyID)) fail("credential ID doesn't match");

    return { keyID: base64(input.keyID), spki: base64(leaf!.spki), counter: 0, appID, environment, createdAt: input.now.toISOString() };
  } catch (error) {
    if (error instanceof InvalidCBOR || error instanceof InvalidDER) fail(`unreadable: ${error.message}`);
    throw error;
  }
}

/** Checks an assertion from an attested key over `clientDataHash`; returns its counter, which the caller stores. */
export async function verifyAssertion(input: { assertion: Uint8Array; key: AttestedKey; clientDataHash: Uint8Array }): Promise<number> {
  try {
    const object = decodeCBOR(input.assertion);
    const signature = field(object, "signature");
    const authData = field(object, "authenticatorData");
    if (!(signature instanceof Uint8Array) || !(authData instanceof Uint8Array)) fail("missing fields");

    const nonce = await sha256(authData, input.clientDataHash);
    const signer = { spki: fromBase64(input.key.spki), curve: { name: "P-256" as const, size: 32 } };
    if (!(await verifySignature(signer, "SHA-256", signature, nonce))) fail("bad signature");

    const data = authenticatorData(authData, false);
    if ((await matchingAppID(data.rpIDHash)) !== input.key.appID) fail("different app");
    if (data.counter <= input.key.counter) fail("counter didn't go up");
    return data.counter;
  } catch (error) {
    if (error instanceof InvalidCBOR || error instanceof InvalidDER) fail(`unreadable: ${error.message}`);
    throw error;
  }
}

// MARK: - Challenges

/** How long a challenge stays good: enough for the app to attest or upload, not to stockpile them. */
const challengeLifetime = 5 * 60 * 1000;

async function hmac(secret: string, data: Uint8Array): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(`attest:${secret}`), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, data)).subarray(0, 16);
}

/** A stateless challenge: the time, random bytes and a MAC over both, base64url. */
export async function newChallenge(secret: string, now = Date.now()): Promise<string> {
  const body = new Uint8Array(24);
  new DataView(body.buffer).setFloat64(0, now);
  crypto.getRandomValues(body.subarray(8));
  const mac = await hmac(secret, body);
  const joined = new Uint8Array(40);
  joined.set(body);
  joined.set(mac, 24);
  return base64(joined).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

export async function checkChallenge(secret: string, challenge: string, now = Date.now()): Promise<boolean> {
  let bytes: Uint8Array;
  try {
    bytes = fromBase64(challenge);
  } catch {
    return false;
  }
  if (bytes.length !== 40) return false;
  const body = bytes.subarray(0, 24);
  if (!equal(await hmac(secret, body), bytes.subarray(24))) return false;
  const issued = new DataView(body.buffer, body.byteOffset, 8).getFloat64(0);
  return now >= issued - 60_000 && now - issued <= challengeLifetime;
}

/** What an upload's assertion signs: its challenge and the list's JSON, so it can't be reused for another list. */
export async function uploadClientDataHash(challenge: string, listJSON: Uint8Array): Promise<Uint8Array> {
  const listHash = [...(await sha256(listJSON))].map((byte) => byte.toString(16).padStart(2, "0")).join("");
  return sha256(new TextEncoder().encode(`${challenge}.${listHash}`));
}
