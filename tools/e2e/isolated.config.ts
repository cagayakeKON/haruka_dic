import { defineConfig } from "@playwright/test";
import path from "node:path";

const runId = process.env.HARUKA_TEST_RUN_ID;
const privateOutputDir =
  runId && /^[0-9a-f]{32}$/.test(runId)
    ? path.resolve("../../dev/.local/b1", runId, "playwright-output")
    : path.resolve("../../artifacts/e2e/isolated-results");

export default defineConfig({
  testDir: "./isolated",
  timeout: 120_000,
  fullyParallel: false,
  retries: 0,
  reporter: [
    ["list"],
    ["json", { outputFile: "../../artifacts/e2e/isolated-results.json" }],
  ],
  outputDir: privateOutputDir,
  use: {
    baseURL: "https://localhost:18443",
    ignoreHTTPSErrors: true,
    testIdAttribute: "flt-semantics-identifier",
    viewport: { width: 1280, height: 800 },
    trace: "off",
    screenshot: "off",
    video: "off",
  },
});
