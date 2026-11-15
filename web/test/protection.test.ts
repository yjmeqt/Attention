import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import worker from "../src/index";

const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0x10]);
let nextIP = 1;

function form(items: unknown[], thumbs: string[] = []) {
  const body = new FormData();
  body.set("list", JSON.stringify({ v: 1, title: "t", items }));
  for (const name of thumbs) body.set(name, new File([jpeg], `${name}.jpg`));
  return body;
}

/** Calls the Worker with some variables overridden. */
async function post(body: FormData, vars: Record<string, string> = {}) {
  const request = new Request("https://attention.test/api/lists", {
    method: "POST",
    body,
    headers: { "CF-Connecting-IP": `10.2.0.${nextIP++}` },
  });
  const overridden = {
    LISTS: env.LISTS,
    UPLOAD_LIMITER: env.UPLOAD_LIMITER,
    UPLOAD_QUOTA: env.UPLOAD_QUOTA,
    UPLOADS_ENABLED: env.UPLOADS_ENABLED,
    DAILY_UPLOAD_LIMIT: env.DAILY_UPLOAD_LIMIT,
    REPORT_URL: env.REPORT_URL,
    ...vars,
  } as unknown as Env;
  return worker.fetch(request as Request<unknown, IncomingRequestCfProperties>, overridden);
}

const link = { kind: "link", url: "https://example.com", title: "x" };

describe("upload protection", () => {
  it("stops uploads when the kill switch is off", async () => {
    const response = await post(form([link]), { UPLOADS_ENABLED: "false" });
    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({ error: "uploads_disabled" });
  });

  it("stops uploads once the daily limit is reached", async () => {
    const response = await post(form([link]), { DAILY_UPLOAD_LIMIT: "0" });
    expect(response.status).toBe(429);
    expect(await response.json()).toMatchObject({ error: "daily_limit" });
  });

  it("counts per UTC day", async () => {
    const quota = env.UPLOAD_QUOTA.get(env.UPLOAD_QUOTA.idFromName("count-test"));
    const day = new Date("2030-01-01T23:59:00Z");
    expect([await quota.take(2, day), await quota.take(2, day), await quota.take(2, day)]).toEqual([true, true, false]);
    expect(await quota.take(2, new Date("2030-01-02T00:00:00Z"))).toBe(true);
  });

  it("keeps thumbnails for the first 20 items only", async () => {
    const items = Array.from({ length: 22 }, (_, i) => ({ ...link, thumb: `t${i}` }));
    const response = await post(form(items, items.map((item) => item.thumb)));
    expect(response.status).toBe(201);
    const { id } = await response.json<{ id: string }>();
    const stored = await env.LISTS.list({ prefix: `lists/${id}/` });
    expect(stored.objects.map((object) => object.key).filter((key) => key.endsWith(".jpg"))).toHaveLength(20);
    const list = await (await env.LISTS.get(`lists/${id}/list.json`))!.json<{ items: { thumb?: unknown }[] }>();
    expect(list.items[19]!.thumb).toBe(true);
    expect(list.items[20]!.thumb).toBeUndefined();
  });
});
