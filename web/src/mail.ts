/**
 Mail to support@ and report@attentioncard.com, which Email Routing hands to this Worker.
 Each message is kept as-is in the private `attention-mail` bucket instead of being forwarded;
 `npm run mail` lists and downloads them.

 Key: <YYYY-MM-DD>/<ISO time>-<random>.eml, so a listing sorts by date.
*/

/** Larger messages are refused; Email Routing itself accepts up to 25 MB. */
export const maxMailBytes = 10 * 1024 * 1024;

export async function receiveMail(message: ForwardableEmailMessage, env: Env): Promise<void> {
  if (message.rawSize > maxMailBytes) {
    message.setReject("Message too large; please send it without big attachments.");
    return;
  }
  // Shares the upload counter's Durable Object class, under its own name and limit.
  const quota = env.UPLOAD_QUOTA.get(env.UPLOAD_QUOTA.idFromName("mail"));
  if (!(await quota.take(Number(env.DAILY_MAIL_LIMIT) || 0))) {
    message.setReject("Mailbox is full for today; please try again tomorrow.");
    return;
  }

  const now = new Date().toISOString();
  const key = `${now.slice(0, 10)}/${now}-${crypto.randomUUID().slice(0, 8)}.eml`;
  const raw = await new Response(message.raw).arrayBuffer();
  await env.MAIL.put(key, raw, {
    httpMetadata: { contentType: "message/rfc822" },
    customMetadata: {
      from: message.from.slice(0, 320),
      to: message.to.slice(0, 320),
      // Still MIME-encoded when non-ASCII; the mail script decodes it.
      subject: (message.headers.get("Subject") ?? "").slice(0, 500),
    },
  });
}
