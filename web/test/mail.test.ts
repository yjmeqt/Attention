import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import worker from "../src/index";
import { maxMailBytes } from "../src/mail";

function message(raw: string, size = raw.length) {
  const rejected: string[] = [];
  const msg = {
    from: "someone@example.com",
    to: "support@attentioncard.com",
    headers: new Headers({ Subject: "=?utf-8?B?5rWL6K+V?=" }),
    raw: new Response(raw).body!,
    rawSize: size,
    setReject: (reason: string) => rejected.push(reason),
    forward: async () => ({ messageId: "" }),
    reply: async () => ({ messageId: "" }),
  };
  return { msg: msg as unknown as ForwardableEmailMessage, rejected };
}

const raw = "From: someone@example.com\r\nTo: support@attentioncard.com\r\nSubject: =?utf-8?B?5rWL6K+V?=\r\n\r\nHello\r\n";

describe("mail", () => {
  it("stores the raw message with its sender and subject", async () => {
    const { msg, rejected } = message(raw);
    await worker.email(msg, env);
    expect(rejected).toEqual([]);
    const listed = await env.MAIL.list({ include: ["customMetadata"] });
    expect(listed.objects).toHaveLength(1);
    const object = listed.objects[0]!;
    expect(object.key).toMatch(/^\d{4}-\d{2}-\d{2}\/\d{4}-.+\.eml$/);
    expect(object.customMetadata).toEqual({ from: "someone@example.com", to: "support@attentioncard.com", subject: "=?utf-8?B?5rWL6K+V?=" });
    expect(await (await env.MAIL.get(object.key))!.text()).toBe(raw);
  });

  it("refuses messages that are too large", async () => {
    const { msg, rejected } = message(raw, maxMailBytes + 1);
    await worker.email(msg, env);
    expect(rejected).toHaveLength(1);
  });

  it("refuses mail once the daily limit is reached", async () => {
    const { msg, rejected } = message(raw);
    await worker.email(msg, { ...pick(env), DAILY_MAIL_LIMIT: "0" } as unknown as Env);
    expect(rejected[0]).toContain("tomorrow");
  });
});

function pick(e: Env) {
  return { MAIL: e.MAIL, UPLOAD_QUOTA: e.UPLOAD_QUOTA, DAILY_MAIL_LIMIT: e.DAILY_MAIL_LIMIT };
}
