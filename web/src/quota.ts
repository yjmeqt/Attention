import { DurableObject } from "cloudflare:workers";

/**
 Counts uploads across the whole site, per UTC day, so the worst-case R2 bill has a ceiling
 however many IPs an abuser uses. One instance, named "global".
*/
export class UploadQuota extends DurableObject<Env> {
  /** Takes one upload from today's allowance; false once `limit` is reached. */
  async take(limit: number, now = new Date()): Promise<boolean> {
    const day = now.toISOString().slice(0, 10);
    // Storage calls don't let other requests interleave, so this read-modify-write is atomic.
    const stored = await this.ctx.storage.get<{ day: string; count: number }>("today");
    const count = stored?.day === day ? stored.count : 0;
    if (count >= limit) return false;
    await this.ctx.storage.put("today", { day, count: count + 1 });
    return true;
  }
}
