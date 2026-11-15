import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      // Most tests upload without an assertion; test/attest.test.ts checks "require" itself.
      miniflare: { bindings: { IMAGE_KEY: "test-key", ATTEST_MODE: "log" } },
    }),
  ],
});
