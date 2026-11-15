/**
 Just enough CBOR (RFC 8949) to read App Attest's attestation and assertion objects: unsigned and negative
 integers, byte and text strings, arrays, maps, and false/true/null. Definite lengths only, as Apple sends.
*/

export type CBOR = number | string | Uint8Array | boolean | null | CBOR[] | Map<CBOR, CBOR>;

export class InvalidCBOR extends Error {}

export function decodeCBOR(bytes: Uint8Array): CBOR {
  const reader = { offset: 0 };
  const value = item(bytes, reader, 0);
  if (reader.offset !== bytes.length) throw new InvalidCBOR("trailing bytes");
  return value;
}

function item(bytes: Uint8Array, reader: { offset: number }, depth: number): CBOR {
  if (depth > 16) throw new InvalidCBOR("too deep");
  const initial = byte(bytes, reader);
  const major = initial >> 5;
  const info = initial & 0x1f;
  if (major === 7) {
    if (info === 20) return false;
    if (info === 21) return true;
    if (info === 22) return null;
    throw new InvalidCBOR(`unsupported simple value ${info}`);
  }
  const argument = length(bytes, reader, info);
  switch (major) {
    case 0:
      return argument;
    case 1:
      return -1 - argument;
    case 2:
      return take(bytes, reader, argument);
    case 3:
      return new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(take(bytes, reader, argument));
    case 4: {
      const array: CBOR[] = [];
      for (let index = 0; index < argument; index++) array.push(item(bytes, reader, depth + 1));
      return array;
    }
    case 5: {
      const map = new Map<CBOR, CBOR>();
      for (let index = 0; index < argument; index++) map.set(item(bytes, reader, depth + 1), item(bytes, reader, depth + 1));
      return map;
    }
    default:
      throw new InvalidCBOR(`unsupported major type ${major}`);
  }
}

function byte(bytes: Uint8Array, reader: { offset: number }): number {
  if (reader.offset >= bytes.length) throw new InvalidCBOR("truncated");
  return bytes[reader.offset++]!;
}

function length(bytes: Uint8Array, reader: { offset: number }, info: number): number {
  if (info < 24) return info;
  const size = info === 24 ? 1 : info === 25 ? 2 : info === 26 ? 4 : info === 27 ? 8 : 0;
  if (size === 0) throw new InvalidCBOR("indefinite or reserved length");
  let value = 0;
  for (let index = 0; index < size; index++) value = value * 256 + byte(bytes, reader);
  if (!Number.isSafeInteger(value)) throw new InvalidCBOR("length too large");
  return value;
}

function take(bytes: Uint8Array, reader: { offset: number }, count: number): Uint8Array {
  if (reader.offset + count > bytes.length) throw new InvalidCBOR("truncated");
  const slice = bytes.subarray(reader.offset, reader.offset + count);
  reader.offset += count;
  return slice;
}

/** A map's value for a text key, or undefined. */
export function field(map: CBOR, key: string): CBOR | undefined {
  return map instanceof Map ? map.get(key) : undefined;
}
