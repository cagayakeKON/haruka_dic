import { randomUUID } from "node:crypto";
import { defineConfig } from "@playwright/test";

const evidence = `../../artifacts/e2e/live-${randomUUID()}`;

// Started explicitly by scripts/dev.py; this suite never adopts or stops a server.
export default defineConfig({
  testDir: "./live",
  timeout: 60_000,
  fullyParallel: false,
  forbidOnly: true,
  retries: 0,
  outputDir: `${evidence}/results`,
  reporter: [["list"], ["json", { outputFile: `${evidence}/results.json` }]],
  use: {
    baseURL: "http://localhost:5173",
    testIdAttribute: "flt-semantics-identifier",
    viewport: { width: 1280, height: 800 },
    trace: "off",
    screenshot: "off",
    video: "off",
  },
});
