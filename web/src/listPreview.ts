/**
 A shared list's link preview image: a square picture of the list as a two-column feed, which the app
 renders (docs/list-sharing.md) and uploads as the `preview` part; it's stored as lists/<id>/og.jpg.
 Square so Attention's own link cards, and chat apps that crop to a square, show all of it.
 Lists without one use the template, public/img/og-list-<lang>.png (made by scripts/og.mjs).
*/

export const previewLimits = {
  bytes: 150 * 1024,
  minWidth: 600,
  maxWidth: 1200,
} as const;

export type PreviewLang = "en" | "zh" | "zh-hant";

export function previewLang(tag: string): PreviewLang {
  const lower = tag.toLowerCase();
  if (!lower.startsWith("zh")) return "en";
  return /hant|-tw|-hk|-mo/.test(lower) ? "zh-hant" : "zh";
}

export function templatePath(lang: PreviewLang): string {
  return `/img/og-list-${lang}.png`;
}

/** Width and height from a JPEG's frame header, or null if it isn't a readable JPEG. */
export function jpegSize(bytes: Uint8Array): { width: number; height: number } | null {
  if (bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;
  let offset = 2;
  while (offset + 9 < bytes.length) {
    if (bytes[offset] !== 0xff) return null;
    const marker = bytes[offset + 1]!;
    if (marker === 0xff) {
      offset += 1; // fill byte
      continue;
    }
    const length = (bytes[offset + 2]! << 8) | bytes[offset + 3]!;
    // SOF0–SOF15, except DHT (C4), JPG (C8) and DAC (CC), carry the frame size.
    if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
      const height = (bytes[offset + 5]! << 8) | bytes[offset + 6]!;
      const width = (bytes[offset + 7]! << 8) | bytes[offset + 8]!;
      return width && height ? { width, height } : null;
    }
    if (length < 2) return null;
    offset += 2 + length;
  }
  return null;
}

/** Why an uploaded preview is refused, with the HTTP status, or null when it's fine. */
export function checkPreview(bytes: Uint8Array): { status: 400 | 413; message: string } | null {
  if (bytes.byteLength > previewLimits.bytes) {
    return { status: 413, message: `The preview is larger than ${previewLimits.bytes / 1024} KB.` };
  }
  const size = jpegSize(bytes);
  if (!size) return { status: 400, message: "The preview isn't a JPEG." };
  if (size.width < previewLimits.minWidth || size.width > previewLimits.maxWidth) {
    return { status: 400, message: `The preview must be ${previewLimits.minWidth}–${previewLimits.maxWidth} px wide, not ${size.width}.` };
  }
  // Square, allowing a pixel of rounding.
  if (Math.abs(size.height - size.width) > 1) {
    return { status: 400, message: `The preview must be square, not ${size.width}×${size.height}.` };
  }
  return null;
}
