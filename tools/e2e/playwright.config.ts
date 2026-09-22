import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  timeout: 30_000,
  fullyParallel: false,
  forbidOnly: true,
  retries: 0,
  outputDir: "../../artifacts/e2e/results",
  reporter: [
    ["list"],
    ["json", { outputFile: "../../artifacts/e2e/results.json" }],
  ],
  use: {
    baseURL: "http://127.0.0.1:5174",
    testIdAttribute: "flt-semantics-identifier",
    viewport: { width: 1280, height: 800 },
    trace: "off",
    screenshot: "off",
    video: "off",
  },
  webServer: {
    command: "node server.ts",
    url: "http://127.0.0.1:5174",
    reuseExistingServer: false,
    timeout: 15_000,
  },
});
