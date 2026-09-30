import { defineConfig } from "@playwright/test";
import path from "node:path";
import { readFileSync } from "node:fs";

const runId = process.env.HARUKA_TEST_RUN_ID;
const privateOutputDir =
  runId && /^[0-9a-f]{32}$/.test(runId)
    ? path.resolve("../../dev/.local/b1", runId, "playwright-output")
    : path.resolve("../../artifacts/e2e/isolated-results");
const runtimeFile =
  runId && /^[0-9a-f]{32}$/.test(runId)
    ? path.resolve("../../dev/.local/b1", runId, "runtime.env")
    : null;
const origin = runtimeFile
  ? readFileSync(runtimeFile, "utf8")
      .split(/\r?\n/)
      .find((line) => line.startsWith("HARUKA_PUBLIC_BASE_URL="))
      ?.slice("HARUKA_PUBLIC_BASE_URL=".length)
  : "https://localhost:18443";
if (
  !origin ||
  !["http://localhost:18443", "https://localhost:18443"].includes(origin)
) {
  throw new Error("Isolated Web origin must be the declared loopback target");
}

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
    baseURL: origin,
    ignoreHTTPSErrors: origin.startsWith("https://"),
    testIdAttribute: "flt-semantics-identifier",
    viewport: { width: 1280, height: 800 },
    trace: "off",
    screenshot: "off",
    video: "off",
  },
});
