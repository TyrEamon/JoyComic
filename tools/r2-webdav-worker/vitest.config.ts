import { cloudflareTest } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: {
        bindings: {
          DAV_USERNAME: "joycomic-test",
          DAV_PASSWORD: "test-password",
        },
      },
    }),
  ],
});
