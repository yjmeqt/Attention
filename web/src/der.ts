/**
 Just enough DER (ASN.1) and X.509 to check App Attest certificates with WebCrypto: walk a certificate,
 find its signed part, signature, public key, validity and extensions.
*/

export class InvalidDER extends Error {}

export type Node = {
  tag: number;
  /** The whole element, tag and length included. */
  bytes: Uint8Array;
  content: Uint8Array;
};

export function parse(bytes: Uint8Array): Node {
  const [node, end] = element(bytes, 0);
  if (end !== bytes.length) throw new InvalidDER("trailing bytes");
  return node;
}

function element(bytes: Uint8Array, start: number): [Node, number] {
  if (start + 2 > bytes.length) throw new InvalidDER("truncated");
  const tag = bytes[start]!;
  if ((tag & 0x1f) === 0x1f) throw new InvalidDER("high tag numbers aren't used here");
  let offset = start + 1;
  let size = bytes[offset++]!;
  if (size & 0x80) {
    const count = size & 0x7f;
    if (count === 0 || count > 4) throw new InvalidDER("bad length");
    size = 0;
    for (let index = 0; index < count; index++) {
      if (offset >= bytes.length) throw new InvalidDER("truncated");
      size = size * 256 + bytes[offset++]!;
    }
  }
  const end = offset + size;
  if (end > bytes.length) throw new InvalidDER("truncated");
  return [{ tag, bytes: bytes.subarray(start, end), content: bytes.subarray(offset, end) }, end];
}

/** The elements inside a constructed one (a SEQUENCE, SET or context-specific wrapper). */
export function children(node: Node): Node[] {
  if (!(node.tag & 0x20)) throw new InvalidDER("not constructed");
  const result: Node[] = [];
  let offset = 0;
  while (offset < node.content.length) {
    const [child, end] = element(node.content, offset);
    result.push(child);
    offset = end;
  }
  return result;
}

export function oid(node: Node): string {
  if (node.tag !== 0x06 || node.content.length === 0) throw new InvalidDER("not an OID");
  const bytes = node.content;
  const parts = [Math.floor(bytes[0]! / 40), bytes[0]! % 40];
  let value = 0;
  for (const byte of bytes.subarray(1)) {
    value = value * 128 + (byte & 0x7f);
    if (!(byte & 0x80)) {
      parts.push(value);
      value = 0;
    }
  }
  return parts.join(".");
}

const ecPublicKey = "1.2.840.10045.2.1";
const curves: Record<string, { name: "P-256" | "P-384"; size: number }> = {
  "1.2.840.10045.3.1.7": { name: "P-256", size: 32 },
  "1.3.132.0.34": { name: "P-384", size: 48 },
};
const signatureHashes: Record<string, "SHA-256" | "SHA-384"> = {
  "1.2.840.10045.4.3.2": "SHA-256",
  "1.2.840.10045.4.3.3": "SHA-384",
};

export type Certificate = {
  /** The signed part, which the issuer's signature covers. */
  tbs: Uint8Array;
  signatureHash: "SHA-256" | "SHA-384";
  /** DER ECDSA-Sig-Value. */
  signature: Uint8Array;
  /** SubjectPublicKeyInfo, for WebCrypto's "spki" import. */
  spki: Uint8Array;
  curve: { name: "P-256" | "P-384"; size: number };
  /** The uncompressed point, 04 || X || Y. */
  publicKey: Uint8Array;
  notBefore: Date;
  notAfter: Date;
  /** Extension values (the OCTET STRING's content) by OID. */
  extensions: Map<string, Uint8Array>;
};

export function certificate(der: Uint8Array): Certificate {
  const [tbs, algorithm, signatureBits] = children(parse(der));
  if (!tbs || !algorithm || !signatureBits || signatureBits.tag !== 0x03) throw new InvalidDER("not a certificate");
  const signatureHash = signatureHashes[oid(children(algorithm)[0]!)];
  if (!signatureHash) throw new InvalidDER("not an ECDSA signature");

  let fields = children(tbs);
  if (fields[0]?.tag === 0xa0) fields = fields.slice(1); // version
  const [, , , validity, , spkiNode, ...rest] = fields;
  if (!validity || !spkiNode) throw new InvalidDER("not a certificate");

  const [keyAlgorithm, keyBits] = children(spkiNode);
  const [keyType, curveOID] = children(keyAlgorithm!);
  if (oid(keyType!) !== ecPublicKey) throw new InvalidDER("not an EC key");
  const curve = curves[oid(curveOID!)];
  if (!curve || keyBits?.tag !== 0x03) throw new InvalidDER("unsupported curve");

  const extensions = new Map<string, Uint8Array>();
  const wrapper = rest.find((node) => node.tag === 0xa3);
  if (wrapper) {
    for (const extension of children(children(wrapper)[0]!)) {
      const parts = children(extension);
      const value = parts.at(-1)!;
      if (value.tag !== 0x04) throw new InvalidDER("bad extension");
      extensions.set(oid(parts[0]!), value.content);
    }
  }

  const [notBefore, notAfter] = children(validity).map(time);
  return {
    tbs: tbs.bytes,
    signatureHash,
    signature: signatureBits.content.subarray(1), // the unused-bits byte
    spki: spkiNode.bytes,
    curve,
    publicKey: keyBits.content.subarray(1),
    notBefore: notBefore!,
    notAfter: notAfter!,
    extensions,
  };
}

function time(node: Node): Date {
  const text = new TextDecoder().decode(node.content);
  // UTCTime YYMMDDHHMMSSZ (years 1950–2049) or GeneralizedTime YYYYMMDDHHMMSSZ.
  const full = node.tag === 0x17 ? `${Number(text.slice(0, 2)) < 50 ? "20" : "19"}${text}` : text;
  const match = full.match(/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/);
  if (!match) throw new InvalidDER("bad time");
  const [, year, month, day, hour, minute, second] = match.map(Number);
  return new Date(Date.UTC(year!, month! - 1, day!, hour!, minute!, second!));
}

/** DER ECDSA-Sig-Value (SEQUENCE { r, s }) to the r || s form WebCrypto verifies. */
export function rawSignature(der: Uint8Array, size: number): Uint8Array {
  const [r, s] = children(parse(der));
  const raw = new Uint8Array(size * 2);
  for (const [index, integer] of [r, s].entries()) {
    if (!integer || integer.tag !== 0x02) throw new InvalidDER("bad signature");
    let value = integer.content;
    while (value.length > size && value[0] === 0) value = value.subarray(1);
    if (value.length > size) throw new InvalidDER("bad signature");
    raw.set(value, index * size + size - value.length);
  }
  return raw;
}

/** The certificate inside a PEM file. */
export function pemBody(pem: string): Uint8Array {
  const base64 = pem.replace(/-----(BEGIN|END) CERTIFICATE-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(base64), (char) => char.charCodeAt(0));
}
