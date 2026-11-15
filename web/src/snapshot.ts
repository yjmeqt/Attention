/** A shared list as the app uploads it and as it's stored. Version 1. */

export const limits = {
  items: 100,
  /** Only the first this-many items keep a thumbnail, which bounds R2 writes per upload. */
  thumbItems: 20,
  title: 100,
  linkTitle: 300,
  site: 100,
  author: 100,
  url: 2048,
  text: 5000,
  /** One JPEG thumbnail. The app aims for 60 KB; this leaves room. */
  thumbBytes: 100 * 1024,
  requestBytes: 4 * 1024 * 1024,
} as const;

export type LinkItem = {
  kind: "link";
  url: string;
  title: string;
  site: string;
  author?: string;
  /** Width ÷ height of the thumbnail. */
  aspect?: number;
  /** In an upload: the multipart part holding the JPEG. Stored: true when `<index>.jpg` exists. */
  thumb?: string | true;
  /** The thumbnail's bottom-edge color as `#rrggbb`, which the app's feed puts behind the text under it. */
  tint?: string;
};

export type TextItem = { kind: "text"; text: string };

export type Item = LinkItem | TextItem;

export type Snapshot = {
  v: 1;
  title: string;
  lang: string;
  createdAt: string;
  items: Item[];
  /** Set by the server when the upload had a preview, stored as lists/<id>/og.jpg: its size in pixels.
   `true` in lists from before the size was kept, whose previews were 1200 × 675. */
  og?: true | { width: number; height: number };
};

export class InvalidSnapshot extends Error {}

function fail(message: string): never {
  throw new InvalidSnapshot(message);
}

function text(value: unknown, field: string, max: number, required = true): string | undefined {
  if (value === undefined || value === null || value === "") {
    if (required) fail(`${field} is required`);
    return undefined;
  }
  if (typeof value !== "string") fail(`${field} must be a string`);
  // Line breaks are kept for text items; everything else is one line.
  const trimmed = value.trim();
  if (required && trimmed === "") fail(`${field} is required`);
  if ([...trimmed].length > max) fail(`${field} is longer than ${max} characters`);
  return trimmed || undefined;
}

function webURL(value: unknown, field: string): string {
  const raw = text(value, field, limits.url)!;
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    fail(`${field} is not a URL`);
  }
  // Anything else (javascript:, data:, file:) would run or leak from the page.
  if (url.protocol !== "https:" && url.protocol !== "http:") fail(`${field} must be http or https`);
  return url.href;
}

function link(raw: Record<string, unknown>, field: string): LinkItem {
  const item: LinkItem = {
    kind: "link",
    url: webURL(raw.url, `${field}.url`),
    title: text(raw.title, `${field}.title`, limits.linkTitle, false) ?? "",
    site: text(raw.site, `${field}.site`, limits.site, false) ?? "",
  };
  const author = text(raw.author, `${field}.author`, limits.author, false);
  if (author) item.author = author;
  if (raw.aspect !== undefined) {
    if (typeof raw.aspect !== "number" || !Number.isFinite(raw.aspect)) fail(`${field}.aspect must be a number`);
    item.aspect = Math.min(Math.max(raw.aspect, 0.25), 4);
  }
  if (typeof raw.tint === "string" && /^#[0-9a-f]{6}$/i.test(raw.tint)) item.tint = raw.tint.toLowerCase();
  if (raw.thumb !== undefined) {
    if (typeof raw.thumb !== "string" || !/^[\w.-]{1,64}$/.test(raw.thumb)) fail(`${field}.thumb must be a part name`);
    item.thumb = raw.thumb;
  }
  return item;
}

/** Checks and normalizes an uploaded list. Unknown fields are dropped. */
export function parseSnapshot(json: unknown, now: Date): Snapshot {
  if (typeof json !== "object" || json === null || Array.isArray(json)) fail("list must be an object");
  const raw = json as Record<string, unknown>;
  if (raw.v !== 1) fail("unsupported version");
  const title = text(raw.title, "title", limits.title)!;
  const lang = typeof raw.lang === "string" && /^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$/.test(raw.lang) ? raw.lang : "en";
  if (!Array.isArray(raw.items) || raw.items.length === 0) fail("items must be a non-empty array");
  if (raw.items.length > limits.items) fail(`more than ${limits.items} items`);
  const items = raw.items.map((value, index): Item => {
    const field = `items[${index}]`;
    if (typeof value !== "object" || value === null) fail(`${field} must be an object`);
    const item = value as Record<string, unknown>;
    switch (item.kind) {
      case "link":
        return link(item, field);
      case "text":
        return { kind: "text", text: text(item.text, `${field}.text`, limits.text)! };
      default:
        fail(`${field}.kind must be link or text`);
    }
  });
  return { v: 1, title, lang, createdAt: now.toISOString(), items };
}

/** True for data that starts like a JPEG file. */
export function isJPEG(bytes: Uint8Array): boolean {
  return bytes.length > 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
}
