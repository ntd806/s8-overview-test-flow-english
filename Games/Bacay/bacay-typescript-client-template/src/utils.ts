import { BacayPacket } from "./types";

export function encodeWsPacket(controllerId: number, actionId: number, body: Uint8Array): Uint8Array {
  const output = new Uint8Array(6 + body.length);
  output[0] = 0x00;
  output[1] = 0x00;
  output[2] = 0x00;
  output[3] = controllerId & 0xff;
  writeUInt16BE(output, 4, actionId);
  output.set(body, 6);
  return output;
}

export function decodeServerPacket(bytes: Uint8Array): BacayPacket {
  return {
    cmd: bytes.length >= 3 ? readUInt16BE(bytes, 1) : null,
    rawHex: toHex(bytes),
    rawBytes: bytes,
  };
}

export function encodeBzString(value: string): Uint8Array {
  const text = new TextEncoder().encode(value || "");
  const out = new Uint8Array(2 + text.length);
  writeUInt16BE(out, 0, text.length);
  out.set(text, 2);
  return out;
}

export function encodeInt32(value: number): Uint8Array {
  const out = new Uint8Array(4);
  new DataView(out.buffer).setInt32(0, Number(value) || 0, false);
  return out;
}

export function encodeInt64(value: number | bigint): Uint8Array {
  const out = new Uint8Array(8);
  new DataView(out.buffer).setBigInt64(0, BigInt(value), false);
  return out;
}

export function concatBytes(...chunks: Uint8Array[]): Uint8Array {
  const total = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;

  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.length;
  }

  return out;
}

export async function normalizeIncomingBytes(data: unknown): Promise<Uint8Array | null> {
  if (!data) return null;

  if (data instanceof Uint8Array) return data;
  if (data instanceof ArrayBuffer) return new Uint8Array(data);

  if (typeof Blob !== "undefined" && data instanceof Blob) {
    return new Uint8Array(await data.arrayBuffer());
  }

  if (typeof (data as { arrayBuffer?: unknown }).arrayBuffer === "function") {
    const buffer = await (data as { arrayBuffer: () => Promise<ArrayBuffer> }).arrayBuffer();
    return new Uint8Array(buffer);
  }

  return null;
}

export function readUInt16BE(bytes: Uint8Array, offset: number): number {
  return ((bytes[offset] << 8) | bytes[offset + 1]) >>> 0;
}

function writeUInt16BE(bytes: Uint8Array, offset: number, value: number): void {
  bytes[offset] = (value >> 8) & 0xff;
  bytes[offset + 1] = value & 0xff;
}

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes, (item) => item.toString(16).padStart(2, "0")).join("");
}
