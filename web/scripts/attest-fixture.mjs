// Makes test/fixtures/attest.json: an App Attest attestation and two assertions shaped like Apple's, signed by a
// throwaway test root instead of Apple's (P-384 root and intermediate, P-256 credential key with the nonce
// extension), for test/attest.test.ts. Needs openssl. Run: node scripts/attest-fixture.mjs
import { execFileSync } from "node:child_process";
import { createHash, createPrivateKey, createPublicKey, sign } from "node:crypto";
import { mkdtempSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const appID = "M3V5P234X3.com.yjmeqt.attn.dev";
const dir = mkdtempSync(join(tmpdir(), "attest-"));
const run = (...args) => execFileSync("openssl", args, { cwd: dir, stdio: ["ignore", "pipe", "pipe"] });
const sha256 = (...parts) => createHash("sha256").update(Buffer.concat(parts)).digest();

// CBOR: maps with text keys, byte strings, text and arrays are all this needs.
function cbor(value) {
  const head = (major, length) => {
    if (length < 24) return Buffer.from([(major << 5) | length]);
    if (length < 256) return Buffer.from([(major << 5) | 24, length]);
    if (length < 65536) return Buffer.from([(major << 5) | 25, length >> 8, length & 0xff]);
    const b = Buffer.alloc(5);
    b[0] = (major << 5) | 26;
    b.writeUInt32BE(length, 1);
    return b;
  };
  if (Buffer.isBuffer(value)) return Buffer.concat([head(2, value.length), value]);
  if (typeof value === "string") return Buffer.concat([head(3, Buffer.byteLength(value)), Buffer.from(value)]);
  if (typeof value === "number") return value >= 0 ? head(0, value) : head(1, -1 - value);
  if (Array.isArray(value)) return Buffer.concat([head(4, value.length), ...value.map(cbor)]);
  const entries = Object.entries(value);
  return Buffer.concat([head(5, entries.length), ...entries.flatMap(([k, v]) => [cbor(/^-?\d+$/.test(k) ? Number(k) : k), cbor(v)])]);
}

// The credential key and its ID: the SHA-256 of its uncompressed public point.
run("ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", "leaf.key");
const leafKey = createPrivateKey(readFileSync(join(dir, "leaf.key")));
const point = createPublicKey(leafKey).export({ format: "der", type: "spki" }).subarray(-65);
const keyID = sha256(point);

const rpIDHash = sha256(Buffer.from(appID));
const counter = (n) => { const b = Buffer.alloc(4); b.writeUInt32BE(n); return b; };
const coseKey = cbor({ 1: 2, 3: -7, "-1": 1, "-2": point.subarray(1, 33), "-3": point.subarray(33) });
const authData = Buffer.concat([
  rpIDHash, Buffer.from([0x40]), counter(0),
  Buffer.from("appattestdevelop"), Buffer.from([0, 32]), keyID, coseKey,
]);
const clientDataHash = sha256(Buffer.from("fixture-challenge"));
const nonce = sha256(authData, clientDataHash);

// Root and intermediate (P-384, like Apple's), then the credential certificate with the nonce extension:
// SEQUENCE { [1] { OCTET STRING nonce } }.
writeFileSync(join(dir, "ca.cnf"), "[ca]\nbasicConstraints=critical,CA:true\nkeyUsage=critical,keyCertSign,cRLSign\n");
writeFileSync(join(dir, "leaf.cnf"), `[leaf]\nbasicConstraints=critical,CA:false\n1.2.840.113635.100.8.2=DER:3024a1220420${nonce.toString("hex")}\n`);
run("ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", "root.key");
run("req", "-new", "-x509", "-key", "root.key", "-sha384", "-days", "3650", "-subj", "/CN=Test App Attestation Root CA", "-extensions", "ca", "-config", "ca.cnf", "-out", "root.pem");
run("ecparam", "-name", "secp384r1", "-genkey", "-noout", "-out", "int.key");
run("req", "-new", "-key", "int.key", "-subj", "/CN=Test App Attestation CA 1", "-out", "int.csr");
run("x509", "-req", "-in", "int.csr", "-CA", "root.pem", "-CAkey", "root.key", "-CAcreateserial", "-sha384", "-days", "3650", "-extfile", "ca.cnf", "-extensions", "ca", "-outform", "DER", "-out", "int.der");
run("x509", "-inform", "DER", "-in", "int.der", "-out", "int.pem");
run("req", "-new", "-key", "leaf.key", "-subj", "/CN=test-credential", "-out", "leaf.csr");
run("x509", "-req", "-in", "leaf.csr", "-CA", "int.pem", "-CAkey", "int.key", "-CAcreateserial", "-sha256", "-days", "3650", "-extfile", "leaf.cnf", "-extensions", "leaf", "-outform", "DER", "-out", "leaf.der");

const attestation = cbor({
  fmt: "apple-appattest",
  attStmt: { x5c: [readFileSync(join(dir, "leaf.der")), readFileSync(join(dir, "int.der"))], receipt: Buffer.from("test-receipt") },
  authData,
});

const assertion = (n, data) => {
  const assertionAuthData = Buffer.concat([rpIDHash, Buffer.from([0x40]), counter(n)]);
  const signature = sign("sha256", sha256(assertionAuthData, sha256(Buffer.from(data))), leafKey);
  return { clientData: data, assertion: cbor({ signature, authenticatorData: assertionAuthData }).toString("base64") };
};

const fixture = {
  appID,
  rootPEM: readFileSync(join(dir, "root.pem"), "utf8"),
  keyID: keyID.toString("base64"),
  clientData: "fixture-challenge",
  attestation: attestation.toString("base64"),
  assertions: [assertion(1, "upload-1"), assertion(2, "upload-2")],
  // A throwaway test key, so tests can sign assertions over their own uploads.
  credentialKey: leafKey.export({ format: "der", type: "pkcs8" }).toString("base64"),
};
mkdirSync(new URL("../test/fixtures/", import.meta.url), { recursive: true });
writeFileSync(new URL("../test/fixtures/attest.json", import.meta.url), JSON.stringify(fixture, null, 2) + "\n");
console.log("wrote test/fixtures/attest.json");
