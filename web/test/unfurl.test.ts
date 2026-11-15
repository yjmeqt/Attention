import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { checkTarget, cleanedForSharing, declaredIcon, displayURL, linkKind, metaTags, qrPath, removingSiteSuffix } from "../src/unfurl";

describe("link rules (ported from the app)", () => {
  it("classifies links", () => {
    expect(linkKind(new URL("https://m.youtube.com/watch?v=a"))).toBe("youtube");
    expect(linkKind(new URL("https://b23.tv/x"))).toBe("bilibili");
    expect(linkKind(new URL("https://twitter.com/a/status/1"))).toBe("x");
    expect(linkKind(new URL("https://notyoutube.com"))).toBe("web");
  });

  it("cleans links for sharing", () => {
    expect(cleanedForSharing(new URL("https://www.youtube.com/watch?v=abc&t=3&si=x")).href).toBe("https://youtu.be/abc");
    expect(cleanedForSharing(new URL("https://youtube.com/shorts/xyz?feature=share")).href).toBe("https://youtu.be/xyz");
    expect(cleanedForSharing(new URL("https://x.com/a/status/1?s=20#m")).href).toBe("https://x.com/a/status/1");
    expect(cleanedForSharing(new URL("https://example.com/p?id=1&utm_source=x&fbclid=y")).href).toBe("https://example.com/p?id=1");
    expect(displayURL(new URL("https://www.example.com/"))).toBe("example.com");
  });

  it("only accepts public web addresses", () => {
    expect(checkTarget("http://example.com/a").href).toBe("https://example.com/a");
    for (const bad of ["ftp://example.com", "https://127.0.0.1", "https://localhost", "https://[::1]/", "https://a.local", "https://example.com:8080", "https://u:p@example.com", "nonsense"]) {
      expect(() => checkTarget(bad), bad).toThrow();
    }
  });

  it("reads Open Graph tags and icons", () => {
    const html = `<title>T - Site</title><meta property="og:title" content="Tom &amp; Jerry"><meta name="og:title" content="second">
      <link rel="icon" href="/16.png" sizes="16x16"><link rel="icon" sizes="64x64" href="/64.png"><link rel="apple-touch-icon" href="/touch.png">`;
    expect(metaTags(html)["og:title"]).toBe("Tom & Jerry");
    expect(declaredIcon(html)).toBe("/touch.png");
    expect(removingSiteSuffix("小红书", "标题 - 小红书")).toBe("标题");
  });

  it("makes a QR path", () => {
    const qr = qrPath("https://youtu.be/abc");
    expect(qr.size).toBeGreaterThanOrEqual(21);
    expect(qr.path).toMatch(/^M\d+ \d+h1v1h-1z/);
  });
});

describe("/api/unfurl and /api/image", () => {
  it("rejects addresses it won't fetch", async () => {
    const response = await SELF.fetch("https://attention.test/api/unfurl?url=https%3A%2F%2F127.0.0.1%2F");
    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({ error: "not_a_url" });
  });

  it("only proxies signed image URLs", async () => {
    const response = await SELF.fetch("https://attention.test/api/image?u=https%3A%2F%2Fexample.com%2Fa.png&s=nope");
    expect(response.status).toBe(403);
  });
});
