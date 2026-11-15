import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { homeLang } from "../src/home";

describe("home page language", () => {
  it("follows the browser's language first", () => {
    expect(homeLang("en-US,en;q=0.9", "CN")).toBe("en");
    expect(homeLang("zh-CN,zh;q=0.9,en;q=0.8", "US")).toBe("zh-Hans");
    expect(homeLang("zh-TW,zh;q=0.9")).toBe("zh-Hant");
    expect(homeLang("zh-Hant-HK")).toBe("zh-Hant");
    expect(homeLang("ja,en;q=0.5")).toBe("en");
    expect(homeLang("en;q=0.4,zh;q=0.8")).toBe("zh-Hans");
  });

  it("uses the country when the browser names neither", () => {
    expect(homeLang("zh", "HK")).toBe("zh-Hant");
    expect(homeLang(null, "CN")).toBe("zh-Hans");
    expect(homeLang("ja", "TW")).toBe("zh-Hant");
    expect(homeLang(null, "DE")).toBe("en");
    expect(homeLang(null)).toBe("en");
  });

  it("serves each language at its own path, and picks one at /", async () => {
    const zh = await SELF.fetch("https://attention.test/", { headers: { "Accept-Language": "zh-CN" } });
    expect(zh.headers.get("Content-Language")).toBe("zh-Hans");
    expect(zh.headers.get("Vary")).toBe("Accept-Language");
    expect(await zh.text()).toContain('<html lang="zh-Hans">');
    const en = await SELF.fetch("https://attention.test/en", { headers: { "Accept-Language": "zh-CN" } });
    const html = await en.text();
    expect(html).toContain('<html lang="en">');
    expect(html).toContain('<meta property="og:image" content="https://attention.test/img/og-en.jpg?v=2">');
    expect(html).toContain('<meta name="apple-itunes-app" content="app-id=6827156660">');
    expect((await SELF.fetch("https://attention.test/zh-hant/")).headers.get("Content-Language")).toBe("zh-Hant");
  });
});
