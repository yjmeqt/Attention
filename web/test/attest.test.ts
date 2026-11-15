import { env, SELF } from "cloudflare:test";
import worker from "../src/index";
import { describe, expect, it } from "vitest";
import { appAttestRootPEM } from "../src/appAttestRoot";
import {
  base64, checkChallenge, fromBase64, newChallenge, sha256, uploadClientDataHash, verifyAssertion, verifyAttestation,
} from "../src/attest";
import { certificate, pemBody } from "../src/der";
import fixture from "./fixtures/attest.json";

const origin = "https://attention.test";
const text = (value: string) => new TextEncoder().encode(value);
const now = new Date();

function attest(overrides: Partial<Parameters<typeof verifyAttestation>[0]> = {}) {
  return verifyAttestation({
    attestation: fromBase64(fixture.attestation),
    keyID: fromBase64(fixture.keyID),
    clientDataHash: overrides.clientDataHash ?? new Uint8Array(0),
    rootPEM: fixture.rootPEM,
    now,
    ...overrides,
  });
}

async function attestedKey() {
  return attest({ clientDataHash: await sha256(text(fixture.clientData)) });
}

/** An assertion like the app's: the test credential key signs SHA-256(authData || clientDataHash), DER-encoded. */
async function signAssertion(counter: number, clientDataHash: Uint8Array, extra = 0): Promise<string> {
  const authData = new Uint8Array(37 + extra);
  authData.fill(0xff, 37);
  authData.set(await sha256(text(fixture.appID)));
  authData[32] = 0x40;
  new DataView(authData.buffer).setUint32(33, counter);
  const key = await crypto.subtle.importKey("pkcs8", fromBase64(fixture.credentialKey), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, await sha256(authData, clientDataHash)));
  const integer = (bytes: Uint8Array) => {
    let value = bytes;
    while (value.length > 1 && value[0] === 0 && !(value[1]! & 0x80)) value = value.subarray(1);
    if (value[0]! & 0x80) value = Uint8Array.of(0, ...value);
    return Uint8Array.of(0x02, value.length, ...value);
  };
  const r = integer(raw.subarray(0, 32)), s = integer(raw.subarray(32));
  const signature = Uint8Array.of(0x30, r.length + s.length, ...r, ...s);
  // CBOR { "signature": bytes, "authenticatorData": bytes }
  const cbor = Uint8Array.of(0xa2, 0x69, ...text("signature"), 0x58, signature.length, ...signature,
    0x71, ...text("authenticatorData"), 0x58, authData.length, ...authData);
  return base64(cbor);
}

describe("App Attest", () => {
  it("reads Apple's root certificate", () => {
    const root = certificate(pemBody(appAttestRootPEM));
    expect(root.curve.name).toBe("P-384");
    expect(root.notAfter.toISOString()).toBe("2045-03-15T00:00:00.000Z");
  });

  it("accepts an attestation that chains to the root, and remembers the key", async () => {
    const key = await attestedKey();
    expect(key).toMatchObject({ keyID: fixture.keyID, counter: 0, appID: fixture.appID, environment: "development" });
  });

  it("refuses attestations that don't check out", async () => {
    const good = await sha256(text(fixture.clientData));
    const cases: [Partial<Parameters<typeof verifyAttestation>[0]>, string][] = [
      [{ clientDataHash: good, rootPEM: appAttestRootPEM }, "bad certificate signature"],
      [{ clientDataHash: await sha256(text("another challenge")) }, "nonce doesn't match"],
      [{ clientDataHash: good, keyID: new Uint8Array(32) }, "key ID doesn't match the certificate"],
      [{ clientDataHash: good, now: new Date("2099-01-01") }, "certificate outside its validity"],
      [{ clientDataHash: good, attestation: text("not cbor") }, "unreadable"],
    ];
    for (const [overrides, message] of cases) {
      await expect(attest(overrides)).rejects.toThrow(message);
    }
  });

  it("reads only the RP ID hash and counter from an assertion's authenticator data", async () => {
    const key = await attestedKey();
    const hash = await sha256(text("upload"));
    // Anything after the counter isn't attested credential data in an assertion, whatever its flags say.
    const assertion = fromBase64(await signAssertion(7, hash, 30));
    expect(await verifyAssertion({ assertion, key, clientDataHash: hash })).toBe(7);
  });

  it("accepts assertions whose counter goes up, and only over what was signed", async () => {
    const key = await attestedKey();
    const [first, second] = fixture.assertions;
    key.counter = await verifyAssertion({ assertion: fromBase64(first!.assertion), key, clientDataHash: await sha256(text(first!.clientData)) });
    expect(key.counter).toBe(1);
    await expect(verifyAssertion({ assertion: fromBase64(first!.assertion), key, clientDataHash: await sha256(text(first!.clientData)) }))
      .rejects.toThrow("counter didn't go up");
    await expect(verifyAssertion({ assertion: fromBase64(second!.assertion), key, clientDataHash: await sha256(text("something else")) }))
      .rejects.toThrow("bad signature");
    expect(await verifyAssertion({ assertion: fromBase64(second!.assertion), key, clientDataHash: await sha256(text(second!.clientData)) })).toBe(2);
  });

  it("signs the same thing as the app: the challenge and the list's JSON", async () => {
    // ios/Tests/ListUploadTests.swift checks the app's side against this string.
    const expected = await sha256(text("abc.44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"));
    expect(await uploadClientDataHash("abc", text("{}"))).toEqual(expected);
  });

  it("makes challenges that expire and can't be forged", async () => {
    const challenge = await newChallenge("secret", 1_000_000);
    expect(await checkChallenge("secret", challenge, 1_000_000 + 60_000)).toBe(true);
    expect(await checkChallenge("secret", challenge, 1_000_000 + 6 * 60_000)).toBe(false);
    expect(await checkChallenge("other", challenge, 1_000_000)).toBe(false);
    expect(await checkChallenge("secret", challenge.slice(0, -2) + "AA", 1_000_000)).toBe(false);
    expect(await checkChallenge("secret", "nope", 1_000_000)).toBe(false);
  });

  it("serves challenges and refuses attestations that don't chain to Apple", async () => {
    const { challenge } = await (await SELF.fetch(`${origin}/api/attest/challenge`)).json<{ challenge: string }>();
    expect(await checkChallenge("test-key", challenge)).toBe(true);
    const post = (body: unknown, ip: string) =>
      SELF.fetch(`${origin}/api/attest`, { method: "POST", body: JSON.stringify(body), headers: { "CF-Connecting-IP": ip } });
    const badChallenge = await post({ keyId: fixture.keyID, attestation: fixture.attestation, challenge: "nope" }, "10.9.0.1");
    expect(await badChallenge.json()).toMatchObject({ error: "invalid_challenge" });
    // The fixture chains to the test root, not Apple's, so the live endpoint refuses it.
    const notApple = await post({ keyId: fixture.keyID, attestation: fixture.attestation, challenge }, "10.9.0.2");
    expect(notApple.status).toBe(400);
    expect(await notApple.json()).toMatchObject({ error: "invalid_attestation", message: "bad certificate signature" });
  });

  it("checks an upload's assertion against the stored key and keeps its counter", async () => {
    const key = await attestedKey();
    const path = `attest/${fixture.keyID.replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "")}`;
    await env.LISTS.put(path, JSON.stringify(key));

    const list = JSON.stringify({ v: 1, title: "Attested", lang: "en", items: [{ kind: "text", text: "hello" }] });
    const upload = async (headers: Record<string, string>, ip: string) => {
      const form = new FormData();
      form.set("list", list);
      return SELF.fetch(`${origin}/api/lists`, { method: "POST", body: form, headers: { "CF-Connecting-IP": ip, ...headers } });
    };
    const { challenge } = await (await SELF.fetch(`${origin}/api/attest/challenge`)).json<{ challenge: string }>();
    const assertion = await signAssertion(5, await uploadClientDataHash(challenge, text(list)));
    const created = await upload({ "X-Attest-Key": fixture.keyID, "X-Attest-Challenge": challenge, "X-Attest-Assertion": assertion }, "10.9.0.3");
    expect(created.status).toBe(201);
    expect((await (await env.LISTS.get(path))!.json<{ counter: number }>()).counter).toBe(5);

    // In "log" mode (the tests' setting), uploads without an assertion still go through.
    expect((await upload({}, "10.9.0.4")).status).toBe(201);
  });

  it("refuses uploads without a valid assertion in \"require\" mode", async () => {
    const strict = { ...env, ATTEST_MODE: "require" } as unknown as typeof env;
    const upload = async (headers: Record<string, string>, ip: string) => {
      const form = new FormData();
      form.set("list", JSON.stringify({ v: 1, title: "Strict", lang: "en", items: [{ kind: "text", text: "hello" }] }));
      return worker.fetch!(new Request(`${origin}/api/lists`, { method: "POST", body: form, headers: { "CF-Connecting-IP": ip, ...headers } }) as never, strict);
    };
    const missing = await upload({}, "10.9.1.1");
    expect(missing.status).toBe(401);
    expect(await missing.json()).toMatchObject({ error: "attestation_required", message: "missing" });
    const { challenge } = await (await SELF.fetch(`${origin}/api/attest/challenge`)).json<{ challenge: string }>();
    const unknown = await upload({ "X-Attest-Key": base64(new Uint8Array(32)), "X-Attest-Challenge": challenge, "X-Attest-Assertion": "AA" }, "10.9.1.2");
    expect(unknown.status).toBe(401);
    expect(await unknown.json()).toMatchObject({ error: "unknown_attest_key" });
  });
});
