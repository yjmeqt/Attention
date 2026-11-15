import { describe, expect, it } from "vitest";
import { newListID, listIDPattern } from "../src/ids";
import { escapeHTML, pageLang, readerLang } from "../src/page";
import { InvalidSnapshot, isJPEG, parseSnapshot } from "../src/snapshot";

const now = new Date("2026-11-14T08:00:00Z");
const link = { kind: "link", url: "https://youtu.be/abc", title: "Video", site: "YouTube" };

describe("parseSnapshot", () => {
  it("normalizes a valid list and sets the date on the server", () => {
    const snapshot = parseSnapshot(
      { v: 1, title: "  周末  ", lang: "zh-Hans", createdAt: "1999-01-01", extra: 1, items: [link, { kind: "text", text: "hi" }] },
      now,
    );
    expect(snapshot).toEqual({
      v: 1,
      title: "周末",
      lang: "zh-Hans",
      createdAt: "2026-11-14T08:00:00.000Z",
      items: [
        { kind: "link", url: "https://youtu.be/abc", title: "Video", site: "YouTube" },
        { kind: "text", text: "hi" },
      ],
    });
  });

  it.each([
    ["javascript: links", { ...link, url: "javascript:alert(1)" }],
    ["data: links", { ...link, url: "data:text/html,hi" }],
    ["relative links", { ...link, url: "/path" }],
    ["unknown kinds", { kind: "image" }],
    ["empty text", { kind: "text", text: "   " }],
    ["text over 5,000 characters", { kind: "text", text: "字".repeat(5001) }],
    ["bad part names", { ...link, thumb: "../x" }],
  ])("rejects %s", (_, item) => {
    expect(() => parseSnapshot({ v: 1, title: "t", items: [item] }, now)).toThrow(InvalidSnapshot);
  });

  it("rejects bad lists", () => {
    expect(() => parseSnapshot({ v: 2, title: "t", items: [link] }, now)).toThrow(InvalidSnapshot);
    expect(() => parseSnapshot({ v: 1, title: "", items: [link] }, now)).toThrow(InvalidSnapshot);
    expect(() => parseSnapshot({ v: 1, title: "t", items: [] }, now)).toThrow(InvalidSnapshot);
    expect(() => parseSnapshot({ v: 1, title: "t", items: Array(101).fill(link) }, now)).toThrow(InvalidSnapshot);
    expect(() => parseSnapshot([], now)).toThrow(InvalidSnapshot);
  });

  it("counts characters, not UTF-16 units", () => {
    expect(() => parseSnapshot({ v: 1, title: "😀".repeat(100), items: [link] }, now)).not.toThrow();
  });

  it("clamps the aspect ratio and falls back to English for odd language tags", () => {
    const snapshot = parseSnapshot({ v: 1, title: "t", lang: "<b>", items: [{ ...link, aspect: 99 }] }, now);
    expect(snapshot.lang).toBe("en");
    expect(snapshot.items[0]).toMatchObject({ aspect: 4 });
  });
});

describe("helpers", () => {
  it("makes 10-character base62 IDs", () => {
    const ids = new Set(Array.from({ length: 1000 }, () => newListID()));
    expect(ids.size).toBe(1000);
    for (const id of ids) expect(id).toMatch(listIDPattern);
  });

  it("recognizes JPEG data", () => {
    expect(isJPEG(new Uint8Array([0xff, 0xd8, 0xff, 0xe0]))).toBe(true);
    expect(isJPEG(new Uint8Array([0x89, 0x50, 0x4e, 0x47]))).toBe(false);
  });

  it("escapes HTML", () => {
    expect(escapeHTML(`<a href="x">'&'</a>`)).toBe("&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;");
  });

  it("picks the page language", () => {
    expect(pageLang("zh-Hans")).toBe("zh-Hans");
    expect(pageLang("zh-Hant-TW")).toBe("zh-Hant");
    expect(pageLang("zh-TW")).toBe("zh-Hant");
    expect(pageLang("ja")).toBe("en");
    expect(readerLang("en-US,en;q=0.9")).toBe("en");
    expect(readerLang(null)).toBe("zh-Hans");
  });
});
