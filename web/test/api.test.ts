import { env, SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

const origin = "https://attention.test";
const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0x10, 0x4a, 0x46, 0x49, 0x46]);

let nextIP = 1;

function upload(list: unknown, parts: Record<string, Uint8Array> = {}, ip = `10.0.0.${nextIP++}`) {
  const form = new FormData();
  form.set("list", JSON.stringify(list));
  for (const [name, bytes] of Object.entries(parts)) form.set(name, new File([bytes], `${name}.jpg`, { type: "image/jpeg" }));
  return SELF.fetch(`${origin}/api/lists`, { method: "POST", body: form, headers: { "CF-Connecting-IP": ip } });
}

const list = {
  v: 1,
  title: "周末要看的 <script>",
  lang: "zh-Hans",
  items: [
    { kind: "link", url: "https://youtu.be/abc", title: "A video", site: "YouTube", author: "Someone", thumb: "t0", aspect: 1.78, tint: "#1A2B3C" },
    { kind: "link", url: "https://example.com/post?x=1&y=2", title: "", site: "", tint: "red; x" },
    { kind: "text", text: "短文本" },
    { kind: "text", text: "长".repeat(400) },
  ],
};

type Created = { id: string; url: string; deleteToken: string };

describe("shared lists", () => {
  it("creates, shows and revokes a list", async () => {
    const created = await upload(list, { t0: jpeg });
    expect(created.status).toBe(201);
    const { id, url, deleteToken } = await created.json<Created>();
    expect(id).toMatch(/^[0-9A-Za-z]{10}$/);
    expect(url).toBe(`${origin}/l/${id}`);
    expect(deleteToken.length).toBeGreaterThan(40);

    // The token itself is never stored.
    const stored = await env.LISTS.get(`lists/${id}/list.json`);
    expect(stored?.customMetadata?.tokenHash).toBeDefined();
    expect(JSON.stringify(stored?.customMetadata)).not.toContain(deleteToken);

    const page = await SELF.fetch(url);
    expect(page.status).toBe(200);
    expect(page.headers.get("Content-Type")).toContain("text/html");
    const html = await page.text();
    expect(html).toContain("周末要看的 &lt;script&gt;");
    expect(html).not.toContain("<script>");
    expect(html).toContain(`href="https://youtu.be/abc"`);
    expect(html).toContain(`href="https://example.com/post?x=1&amp;y=2"`);
    expect(html).toContain(">example.com<"); // title falls back to the host
    expect(html).toContain(`<p class="site">YouTube</p>`);
    expect(html).toContain(`<p class="author">Someone</p>`);
    expect(html).toContain(`src="/l/${id}/0.jpg"`);
    // The band under a photo takes its color, with light text on a dark one; a tint without a photo, or a bad one, is dropped.
    expect(html).toContain(`<div class="body dark" style="background:#1a2b3c">`);
    expect(html).not.toContain("red; x");
    expect(html).toContain(`<p class="site text-site">文字</p>`);
    // The test thumbnails aren't real images, so no preview is made and the template stands in.
    expect(html).toContain(`<meta property="og:image" content="${origin}/img/og-list-zh.png">`);
    expect(html).toContain("4 条");
    expect(html).toContain("<details");
    expect(html).toContain("noindex");

    const thumb = await SELF.fetch(`${url}/0.jpg`);
    expect(thumb.status).toBe(200);
    expect(thumb.headers.get("Content-Type")).toBe("image/jpeg");
    expect(new Uint8Array(await thumb.arrayBuffer())).toEqual(jpeg);
    expect((await SELF.fetch(`${url}/1.jpg`)).status).toBe(404);

    const wrong = await SELF.fetch(`${origin}/api/lists/${id}`, { method: "DELETE", headers: { Authorization: "Bearer nope" } });
    expect(wrong.status).toBe(403);
    expect((await SELF.fetch(`${origin}/api/lists/${id}`, { method: "DELETE" })).status).toBe(401);

    const revoke = () => SELF.fetch(`${origin}/api/lists/${id}`, { method: "DELETE", headers: { Authorization: `Bearer ${deleteToken}` } });
    expect((await revoke()).status).toBe(204);
    expect((await revoke()).status).toBe(204);
    expect((await env.LISTS.list({ prefix: `lists/${id}/` })).objects).toHaveLength(0);

    const gone = await SELF.fetch(url, { headers: { "Accept-Language": "zh-CN" } });
    expect(gone.status).toBe(410);
    expect(await gone.text()).toContain("已被撤回");
    expect((await SELF.fetch(`${url}/0.jpg`)).status).toBe(404);
  });

  it("answers 404 for unknown lists", async () => {
    const page = await SELF.fetch(`${origin}/l/AAAAAAAAAA`, { headers: { "Accept-Language": "en" } });
    expect(page.status).toBe(404);
    expect(await page.text()).toContain("List not found");
    expect((await SELF.fetch(`${origin}/l/bad`)).status).toBe(404);
    const del = await SELF.fetch(`${origin}/api/lists/AAAAAAAAAA`, { method: "DELETE", headers: { Authorization: "Bearer x" } });
    expect(del.status).toBe(404);
  });

  it("rejects bad uploads without storing anything", async () => {
    const before = (await env.LISTS.list()).objects.length;
    const cases: [Response, number, string][] = [
      [await upload({ ...list, items: [{ kind: "link", url: "javascript:alert(1)" }] }), 400, "invalid_list"],
      [await upload(list), 400, "invalid_thumb"], // part t0 is missing
      [await upload(list, { t0: new Uint8Array([0x89, 0x50, 0x4e, 0x47]) }), 400, "invalid_thumb"],
      [await upload(list, { t0: new Uint8Array(200 * 1024).fill(0xff) }), 413, "thumb_too_large"],
      [await SELF.fetch(`${origin}/api/lists`, { method: "POST", body: "{}", headers: { "CF-Connecting-IP": "10.1.1.1" } }), 400, "invalid_form"],
    ];
    for (const [response, status, code] of cases) {
      expect(response.status).toBe(status);
      expect(await response.json()).toMatchObject({ error: code });
    }
    expect((await env.LISTS.list()).objects.length).toBe(before);
  });

  it("limits uploads per IP", async () => {
    const statuses = [];
    for (let i = 0; i < 4; i++) statuses.push((await upload(list, { t0: jpeg }, "10.9.9.9")).status);
    expect(statuses).toEqual([201, 201, 201, 429]);
    expect((await upload(list, { t0: jpeg }, "10.9.9.10")).status).toBe(201);
  });

  it("only allows the right methods", async () => {
    expect((await SELF.fetch(`${origin}/api/lists`)).status).toBe(405);
    expect((await SELF.fetch(`${origin}/l/AAAAAAAAAA`, { method: "POST" })).status).toBe(405);
  });
});
