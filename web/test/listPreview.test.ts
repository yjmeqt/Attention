import { env, SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { checkPreview, jpegSize, previewLang } from "../src/listPreview";

/** A JPEG header (SOI, APP0, SOF0) with the given size, padded to `bytes`. */
export function fakeJPEG(width: number, height: number, bytes = 2000): Uint8Array {
  const head = [
    0xff, 0xd8,
    0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
    0xff, 0xc0, 0x00, 0x11, 0x08, height >> 8, height & 0xff, width >> 8, width & 0xff, 0x03,
    0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
  ];
  const out = new Uint8Array(Math.max(bytes, head.length + 2));
  out.set(head);
  out.set([0xff, 0xd9], out.length - 2);
  return out;
}

const origin = "https://attention.test";

function upload(parts: Record<string, Uint8Array>, ip: string) {
  const form = new FormData();
  form.set("list", JSON.stringify({ v: 1, title: "Weekend", lang: "en", items: [{ kind: "text", text: "hi" }] }));
  for (const [name, bytes] of Object.entries(parts)) form.set(name, new File([bytes], `${name}.jpg`, { type: "image/jpeg" }));
  return SELF.fetch(`${origin}/api/lists`, { method: "POST", body: form, headers: { "CF-Connecting-IP": ip } });
}

describe("list preview", () => {
  it("reads a JPEG's size", () => {
    expect(jpegSize(fakeJPEG(1200, 675))).toEqual({ width: 1200, height: 675 });
    expect(jpegSize(new Uint8Array([0x89, 0x50, 0x4e, 0x47]))).toBeNull();
  });

  it("accepts square JPEGs from 600 to 1200 px wide, up to 150 KB", () => {
    expect(checkPreview(fakeJPEG(1080, 1080))).toBeNull();
    expect(checkPreview(fakeJPEG(800, 801))).toBeNull();
    expect(checkPreview(fakeJPEG(1200, 675))?.message).toContain("square");
    expect(checkPreview(fakeJPEG(1600, 1600))?.message).toContain("wide");
    expect(checkPreview(fakeJPEG(1080, 1080, 151 * 1024))?.status).toBe(413);
    expect(checkPreview(new Uint8Array(500))?.message).toContain("JPEG");
  });

  it("picks the template language", () => {
    expect(previewLang("zh-Hans")).toBe("zh");
    expect(previewLang("zh-Hant-TW")).toBe("zh-hant");
    expect(previewLang("ja")).toBe("en");
  });

  it("uses the app's preview when the upload has one", async () => {
    const created = await upload({ preview: fakeJPEG(1080, 1080) }, "10.4.0.1");
    expect(created.status).toBe(201);
    const { url } = await created.json<{ url: string }>();
    const html = await (await SELF.fetch(url)).text();
    expect(html).toContain(`<meta property="og:image" content="${url}/og.jpg">`);
    expect(html).toContain('<meta property="og:image:width" content="1080">');
    expect(html).toContain('<meta property="og:image:height" content="1080">');
    const image = await SELF.fetch(`${url}/og.jpg`);
    expect(image.status).toBe(200);
    expect(image.headers.get("Content-Type")).toBe("image/jpeg");
  });

  it("uses the template without one, and refuses a bad preview", async () => {
    const created = await upload({}, "10.4.0.2");
    const { url } = await created.json<{ url: string }>();
    expect(await (await SELF.fetch(url)).text()).toContain(`<meta property="og:image" content="${origin}/img/og-list-en.png">`);

    const before = (await env.LISTS.list()).objects.length;
    const bad = await upload({ preview: fakeJPEG(1200, 675) }, "10.4.0.3");
    expect(bad.status).toBe(400);
    expect(await bad.json()).toMatchObject({ error: "invalid_preview" });
    expect((await env.LISTS.list()).objects.length).toBe(before);
  });
});
