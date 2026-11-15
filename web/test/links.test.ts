import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

const origin = "https://attention.test";
const iPhone = { "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1" };
const android = { "User-Agent": "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 Chrome/140.0 Mobile Safari/537.36" };
const windows = { "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/140.0 Safari/537.36" };

async function createList(count: number, ip: string) {
  const form = new FormData();
  const items = Array.from({ length: count }, (_, i) => ({ kind: "link", url: `https://example.com/${i}`, title: `Item ${i}`, site: "Example" }));
  form.set("list", JSON.stringify({ v: 1, title: "Reading", lang: "en", items }));
  const response = await SELF.fetch(`${origin}/api/lists`, { method: "POST", body: form, headers: { "CF-Connecting-IP": ip } });
  return response.json<{ id: string; url: string; deleteToken: string }>();
}

describe("universal links", () => {
  it("serves the apple-app-site-association file on both hosts", async () => {
    for (const host of [origin, "https://open.attentioncard.com"]) {
      const response = await SELF.fetch(`${host}/.well-known/apple-app-site-association`);
      expect(response.status).toBe(200);
      expect(response.headers.get("Content-Type")).toContain("application/json");
      const body = await response.json<any>();
      expect(body.applinks.details[0].appIDs).toContain("M3V5P234X3.com.yjmeqt.attn");
      expect(body.applinks.details[0].components.at(-1)).toMatchObject({ "/": "/l/*" });
    }
  });

  it("sends the open host to the App Store for lists on Apple devices, back to the list elsewhere, and to the main site otherwise", async () => {
    const list = await SELF.fetch("https://open.attentioncard.com/l/AAAAAAAAAA", { redirect: "manual", headers: iPhone });
    expect(list.status).toBe(302);
    expect(list.headers.get("Location")).toBe("https://apps.apple.com/app/id6827156660");
    for (const headers of [android, windows]) {
      const elsewhere = await SELF.fetch("https://open.attentioncard.com/l/AAAAAAAAAA/", { redirect: "manual", headers });
      expect(elsewhere.headers.get("Location")).toBe("https://attentioncard.com/l/AAAAAAAAAA");
    }
    const other = await SELF.fetch("https://open.attentioncard.com/zh", { redirect: "manual" });
    expect(other.headers.get("Location")).toBe("https://attentioncard.com/zh");
  });
});

describe("list page preview", () => {
  it("shows five items and sends the rest to the app", async () => {
    const { id, url } = await createList(8, "10.5.0.1");
    const html = await (await SELF.fetch(url, { headers: iPhone })).text();
    expect(html.match(/<li>/g)).toHaveLength(5);
    expect(html).toContain("Item 4");
    expect(html).not.toContain("Item 5");
    expect(html).toContain("3 more items. See the whole list in Attention.");
    expect(html).toContain(`href="https://open.attentioncard.com/l/${id}"`);
    expect(html).toContain(`content="app-id=6827156660, app-argument=${url}"`);
    expect(html).toContain("This opens the App Store first; once it&#39;s installed, come back and tap again.");
    expect(html).toContain('<meta property="og:locale" content="en_US">');
    expect(html).toContain('<meta name="theme-color" content="#000000" media="(prefers-color-scheme: dark)">');
  });

  it("doesn't send Android or other computers to the App Store", async () => {
    const { id, url } = await createList(2, "10.5.0.4");
    const onAndroid = await (await SELF.fetch(url, { headers: android })).text();
    expect(onAndroid).toContain("Attention is on iPhone, iPad and Mac for now.");
    expect(onAndroid).not.toContain(`href="https://open.attentioncard.com/l/${id}"`);
    expect(onAndroid).not.toContain('class="qr"');

    const onWindows = await (await SELF.fetch(url, { headers: windows })).text();
    expect(onWindows).toContain("Attention is on iPhone, iPad and Mac for now.");
    expect(onWindows).toContain('<svg class="qr"');
    expect(onWindows).not.toContain(`href="https://open.attentioncard.com/l/${id}"`);
  });

  it("tells WeChat readers how to reach the app", async () => {
    const { url } = await createList(2, "10.5.0.2");
    const html = await (await SELF.fetch(url, { headers: { "User-Agent": `${iPhone["User-Agent"]} MicroMessenger/8.0` } })).text();
    expect(html).toContain("Open it in Attention to save it to your library.");
    expect(html).toContain("Open in Browser");
  });

  it("gives the app the whole list as JSON", async () => {
    const { id, url, deleteToken } = await createList(8, "10.5.0.3");
    const response = await SELF.fetch(`${origin}/api/lists/${id}`);
    expect(response.status).toBe(200);
    const list = await response.json<any>();
    expect(list).toMatchObject({ id, url, title: "Reading", lang: "en" });
    expect(list.items).toHaveLength(8);

    await SELF.fetch(`${origin}/api/lists/${id}`, { method: "DELETE", headers: { Authorization: `Bearer ${deleteToken}` } });
    const gone = await SELF.fetch(`${origin}/api/lists/${id}`);
    expect(gone.status).toBe(410);
    expect(await gone.json()).toMatchObject({ error: "revoked" });
    expect((await SELF.fetch(`${origin}/api/lists/AAAAAAAAAA`)).status).toBe(404);
  });
});
