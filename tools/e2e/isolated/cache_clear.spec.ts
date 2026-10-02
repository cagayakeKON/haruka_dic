import { fillPrivateInput } from "./private_input.js";
import { expect, test } from "@playwright/test";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import {
  finishOptionalGuide,
  preserveAccountUiEvidence,
} from "./account_ui.js";

const root = path.resolve("../..");
const runId = process.env.HARUKA_TEST_RUN_ID;
if (!runId || !/^[0-9a-f]{32}$/.test(runId))
  throw new Error("Owned run required");
const directory = path.join(root, "artifacts/stage1/cache-clear-ui");
mkdirSync(directory, { recursive: true });
test.afterEach(async ({ page }, info) => preserveAccountUiEvidence(page, info));

test("actual confirmed local cache clear keeps session and saved owner profile", async ({
  page,
}) => {
  const actor = JSON.parse(
    readFileSync(
      path.join(root, "dev/.local/b1", runId, "account-ui-actor-a.json"),
      "utf8",
    ),
  ) as { email: string; password: string };
  const statuses: { path: string; method: string; status: number }[] = [];
  let supplierSubmissions = 0;
  page.on("response", (response) => {
    const p = new URL(response.url()).pathname;
    if (p.startsWith("/api/v1/users/me/"))
      statuses.push({
        path: p,
        method: response.request().method(),
        status: response.status(),
      });
  });
  page.on("request", (request) => {
    if (
      request.method() === "POST" &&
      /\/provider-credentials\/[^/]+\/test$/.test(
        new URL(request.url()).pathname,
      )
    )
      supplierSubmissions++;
  });
  try {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto("/login");
    await fillPrivateInput(
      page.getByTestId("client.auth.login.email").locator("input"),
      actor.email,
    );
    await fillPrivateInput(
      page.getByTestId("client.auth.login.password").locator("input"),
      actor.password,
    );
    await page.getByTestId("client.auth.login.submit").click();
    await finishOptionalGuide(page);
    await page.goto("/settings/profile");
    const name = page.getByRole("textbox").nth(0);
    await expect(name).toBeVisible();
    await name.click();
    const originalName = await name.inputValue();
    await page.getByRole("button", { name: "本机缓存", exact: true }).click();
    await page.setViewportSize({ width: 390, height: 844 });
    const clear = page.getByText("清除此账号本机缓存", { exact: true });
    await expect(clear).toBeVisible();
    await clear.click();
    const dialog = page.getByRole("alertdialog");
    await expect(dialog).toBeVisible();
    await dialog.getByRole("button", { name: "清理", exact: true }).click();
    await expect(dialog).not.toBeVisible();
    await expect(
      page.locator("span").filter({ hasText: /^本机缓存已清理$/ }),
    ).toBeVisible();
    await page.screenshot({
      path: path.join(directory, "confirmed-mobile.png"),
    });
    await page.goto("/settings/profile");
    await expect(name).toBeVisible();
    await name.click();
    await expect(name).toHaveValue(originalName);
    await page.reload();
    await expect(name).toBeVisible();
    await name.click();
    await expect(name).toHaveValue(originalName);
    expect(
      statuses.some(
        (s) => s.path === "/api/v1/users/me/profile" && s.status === 200,
      ),
    ).toBe(true);
    expect(statuses.every((s) => s.method === "GET")).toBe(true);
    expect(supplierSubmissions).toBe(0);
  } finally {
    writeFileSync(
      path.join(directory, `events-${Date.now().toString()}.json`),
      JSON.stringify(
        {
          statuses,
          supplier_submissions: supplierSubmissions,
          scope:
            "Actual local-clear UI acknowledgement, original persisted profile and session retained; storage accounting is covered by separate lower-layer tests",
        },
        null,
        2,
      ),
    );
  }
});
