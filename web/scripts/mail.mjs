// Reads mail sent to support@ and report@attentioncard.com, stored in R2 by src/mail.ts.
//   npm run mail                 list the newest 30 messages
//   npm run mail -- all          list every message
//   npm run mail -- 3            download message 3 from the list to ~/Downloads/attention-mail/
//   npm run mail -- <key>        download by its R2 key
// Uses your `wrangler login` session.
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join } from "node:path";

const bucket = "attention-mail";
const api = "https://api.cloudflare.com/client/v4";

const token = execFileSync("npx", ["wrangler", "auth", "token"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] })
  .trim().split("\n").filter((line) => line.trim() && !/wrangler|─/.test(line)).at(-1).trim();
const headers = { Authorization: `Bearer ${token}` };

async function json(path) {
  const response = await fetch(`${api}${path}`, { headers });
  const body = await response.json();
  if (!body.success) throw new Error(`${path}: ${JSON.stringify(body.errors)}`);
  return body;
}

const accountID = (await json("/accounts")).result[0].id;
const base = `/accounts/${accountID}/r2/buckets/${bucket}/objects`;

async function listAll() {
  const objects = [];
  let cursor;
  do {
    const body = await json(`${base}?per_page=1000${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ""}`);
    objects.push(...body.result);
    cursor = body.result_info?.is_truncated ? body.result_info.cursor : undefined;
  } while (cursor);
  return objects.sort((a, b) => (a.key < b.key ? 1 : -1));
}

/** Decodes RFC 2047 encoded words such as =?utf-8?B?5rWL6K+V?=. */
function decodeHeader(value = "") {
  return value.replace(/=\?([^?]+)\?([BbQq])\?([^?]*)\?=(\s+(?==\?))?/g, (_, charset, encoding, text) => {
    const bytes = encoding.toUpperCase() === "B"
      ? Buffer.from(text, "base64")
      : Buffer.from(text.replace(/_/g, " ").replace(/=([0-9A-Fa-f]{2})/g, (_, hex) => String.fromCharCode(parseInt(hex, 16))), "latin1");
    try {
      return new TextDecoder(charset).decode(bytes);
    } catch {
      return bytes.toString("utf8");
    }
  });
}

async function download(key) {
  const response = await fetch(`${api}${base}/${key.split("/").map(encodeURIComponent).join("/")}`, { headers });
  if (!response.ok) throw new Error(`No message ${key} (${response.status})`);
  const directory = join(homedir(), "Downloads", "attention-mail");
  mkdirSync(directory, { recursive: true });
  const file = join(directory, basename(key));
  writeFileSync(file, Buffer.from(await response.arrayBuffer()));
  console.log(file);
}

const argument = process.argv[2];
if (argument && argument !== "all" && !/^\d+$/.test(argument)) {
  await download(argument);
} else {
  const objects = await listAll();
  if (/^\d+$/.test(argument ?? "")) {
    const object = objects[Number(argument) - 1];
    if (!object) throw new Error(`There are only ${objects.length} messages.`);
    await download(object.key);
  } else if (objects.length === 0) {
    console.log("No mail.");
  } else {
    const shown = argument === "all" ? objects : objects.slice(0, 30);
    shown.forEach((object, index) => {
      const meta = object.custom_metadata ?? {};
      const when = object.last_modified.slice(0, 16).replace("T", " ");
      console.log(`${String(index + 1).padStart(3)}  ${when}  ${(meta.to ?? "").split("@")[0].padEnd(8)}  ${meta.from ?? ""}`);
      console.log(`     ${decodeHeader(meta.subject) || "(no subject)"}`);
    });
    if (shown.length < objects.length) console.log(`\n${objects.length - shown.length} older; \`npm run mail -- all\` lists them.`);
    console.log("\nDownload one: npm run mail -- <number>");
  }
}
