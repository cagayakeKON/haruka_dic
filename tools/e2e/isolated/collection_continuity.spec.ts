import { fillPrivateInput } from "./private_input.js";
import { expect, test } from "@playwright/test";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import {
  finishOptionalGuide,
  preserveAccountUiEvidence,
} from "./account_ui.js";

test.afterEach(async ({ page }, info) => preserveAccountUiEvidence(page, info));

test("saved owner collection survives reload and dialog/layout events do not reread lists", async ({
  page,
}) => {
  test.setTimeout(120_000);
  const root = path.resolve("../..");
  const runId = process.env.HARUKA_TEST_RUN_ID;
  if (!runId || !/^[0-9a-f]{32}$/.test(runId))
    throw new Error("Owned run required");
  const actor = JSON.parse(
    readFileSync(
      path.join(root, "dev/.local/b1", runId, "account-ui-actor-a.json"),
      "utf8",
    ),
  ) as { email: string; password: string };
  const saved = JSON.parse(
    readFileSync(
      path.join(
        root,
        "artifacts/stage1-frontend-20261001/formal-collection-owner.json",
      ),
      "utf8",
    ),
  ) as { run_id: string; collection_id: string };
  expect(saved.run_id).toBe(runId);
  const reads: Record<string, number> = {};
  let models = 0;
  page.on("request", (r) => {
    const p = new URL(r.url()).pathname;
    if (r.method() === "GET" && /^\/api\/v1\/(collections|materials)/.test(p))
      reads[p] = (reads[p] ?? 0) + 1;
    if (r.method() === "POST" && /\/provider-credentials\/[^/]+\/test$/.test(p))
      models++;
  });
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
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.getByRole("button", { name: "单词本", exact: true }).click();
  const row = page.getByTestId(
    `client.reference.collections.row.${saved.collection_id}`,
  );
  await expect(row).toBeVisible({ timeout: 30_000 });
  await page.reload();
  await expect(row).toBeVisible({ timeout: 30_000 });
  await row.click();
  await expect(page.getByRole("dialog")).toBeVisible();
  await page.screenshot({
    path: path.join(
      root,
      "artifacts/stage1-frontend-20261001/formal-collection-desktop-dialog.png",
    ),
  });
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "关闭", exact: true })
    .click();
  await expect(row).toBeVisible();
  const stable = { ...reads };
  await row.click();
  await expect(page.getByRole("dialog")).toBeVisible();
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({
    path: path.join(
      root,
      "artifacts/stage1-frontend-20261001/formal-collection-mobile-dialog.png",
    ),
  });
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "关闭", exact: true })
    .click();
  await expect(row).toBeVisible();
  await page.waitForTimeout(700);
  expect(reads).toEqual(stable);
  expect(models).toBe(0);
  writeFileSync(
    path.join(
      root,
      "artifacts/stage1-frontend-20261001/formal-collection-continuity.json",
    ),
    JSON.stringify(
      {
        run_id: runId,
        result: "passed",
        steps: [
          "collection visible after actual reload",
          "desktop word dialog actual open/close",
          "mobile resize and same dialog actual close",
          "same lists no extra GET after repeat dialog/resize",
        ],
        reads,
        model_submissions: models,
        limitations: ["cross-account isolation separate pending"],
      },
      null,
      2,
    ),
  );
});
