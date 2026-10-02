import { fillPrivateInput } from "./private_input.js";
import { expect, test } from "@playwright/test";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import {
  finishOptionalGuide,
  preserveAccountUiEvidence,
} from "./account_ui.js";

test.afterEach(async ({ page }, info) => {
  await preserveAccountUiEvidence(page, info);
  if (new URL(page.url()).pathname === "/reference/materials") {
    writeFileSync(
      path.resolve(
        "../../artifacts/stage1-frontend-20261001/collection-reader-observed.txt",
      ),
      await page.locator("body").ariaSnapshot(),
    );
  }
});

test("existing owner selects published source and persists a collection through the dialog", async ({
  page,
}) => {
  test.setTimeout(150_000);
  const runId = process.env.HARUKA_TEST_RUN_ID;
  if (!runId || !/^[0-9a-f]{32}$/.test(runId))
    throw new Error("Owned run required");
  const root = path.resolve("../..");
  const actor = JSON.parse(
    readFileSync(
      path.join(root, "dev/.local/b1", runId, "account-ui-actor-a.json"),
      "utf8",
    ),
  ) as { email: string; password: string };
  let modelSubmissions = 0;
  page.on("request", (request) => {
    if (
      request.method() === "POST" &&
      /\/provider-credentials\/[^/]+\/test$/.test(
        new URL(request.url()).pathname,
      )
    )
      modelSubmissions++;
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
  await page.getByRole("button", { name: "材料库", exact: true }).click();
  const row = page.locator(
    '[flt-semantics-identifier^="client.reference.materials.row."]',
  );
  await expect(row).toHaveCount(1);
  await row.click();
  const block = page.getByRole("group", {
    name: "青い空を見上げた。",
    exact: true,
  });
  await expect(block).toHaveCount(1);
  const bounds = await block.boundingBox();
  if (!bounds) throw new Error("Published source not visible");
  let selected = "";
  for (const start of [37, 32, 27, 42]) {
    const current = await block.boundingBox();
    if (!current)
      throw new Error("Published source disappeared during selection");
    const y = current.y + current.height / 2;
    await page.mouse.click(current.x + 160, y);
    await page.mouse.move(current.x + start, y);
    await page.mouse.down();
    await page.waitForTimeout(750);
    await page.mouse.move(current.x + start + 18, y, { steps: 8 });
    await page.mouse.up();
    // Flutter's canvas selection exposes the text in its visible toolbar.
    await page.waitForTimeout(300);
    selected = (await page
      .getByRole("group", { name: "选句学习 空", exact: true })
      .isVisible())
      ? "空"
      : "";
    if (selected === "空") break;
  }
  expect(selected).toBe("空");
  const resolved = page.waitForResponse(
    (r) =>
      new URL(r.url()).pathname === "/api/v1/explanations/resolve" &&
      r.request().method() === "POST",
  );
  await page
    .getByRole("group", { name: "选句学习 空", exact: true })
    .getByRole("button", { name: "查询", exact: true })
    .click();
  expect((await resolved).status()).toBe(200);
  const saved = page.waitForResponse(
    (r) =>
      new URL(r.url()).pathname === "/api/v1/collections" &&
      r.request().method() === "POST",
  );
  await page.getByTestId("client.reference.collection.save").click();
  const response = await saved;
  expect(response.status()).toBe(201);
  const body = (await response.json()) as { data: { id: string } };
  expect(body.data.id).toMatch(/^[0-9a-f-]{36}$/);
  await expect(
    page.getByTestId("client.reference.collection.saved_state"),
  ).toBeVisible();
  await page.screenshot({
    path: path.join(
      root,
      "artifacts/stage1-frontend-20261001/formal-collection-saved-dialog.png",
    ),
  });
  expect(modelSubmissions).toBe(0);
  writeFileSync(
    path.join(
      root,
      "artifacts/stage1-frontend-20261001/formal-collection-owner.json",
    ),
    JSON.stringify(
      {
        run_id: runId,
        result: "passed",
        collection_id: body.data.id,
        model_submissions: modelSubmissions,
        steps: [
          "actual published source pointer selection",
          "authorized resolve existing persisted card",
          "collection POST201 via same word dialog",
          "saved state visible",
        ],
        limitations: [
          "cross-account isolation and reload not yet verified in this node",
        ],
      },
      null,
      2,
    ),
  );
});
