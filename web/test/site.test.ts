import { env, SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

const origin = "https://attention.test";

describe("site", () => {
  it("sets security headers on Worker responses", async () => {
    for (const path of ["/l/AAAAAAAAAA", "/api/nope"]) {
      const response = await SELF.fetch(`${origin}${path}`);
      expect(response.headers.get("Strict-Transport-Security")).toContain("max-age=31536000");
      expect(response.headers.get("Referrer-Policy")).toBe("no-referrer");
      expect(response.headers.get("X-Frame-Options")).toBe("DENY");
    }
  });

  it("says a list was removed after a takedown", async () => {
    await env.LISTS.put("revoked/BBBBBBBBBB", JSON.stringify({ reason: "takedown", at: "2026-11-14T00:00:00Z" }));
    const page = await SELF.fetch(`${origin}/l/BBBBBBBBBB`, { headers: { "Accept-Language": "zh-CN" } });
    expect(page.status).toBe(410);
    expect(await page.text()).toContain("已被移除");
  });

  it("links Report to the report address with the list's URL", async () => {
    const form = new FormData();
    form.set("list", JSON.stringify({ v: 1, title: "t", items: [{ kind: "text", text: "hi" }] }));
    const created = await SELF.fetch(`${origin}/api/lists`, { method: "POST", body: form, headers: { "CF-Connecting-IP": "10.3.0.1" } });
    const { url } = await created.json<{ url: string }>();
    const html = await (await SELF.fetch(url)).text();
    expect(html).toContain(`href="mailto:report@attentioncard.com?subject=Report%20shared%20list&amp;body=${encodeURIComponent(url)}"`);
  });
});
