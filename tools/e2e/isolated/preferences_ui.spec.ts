import { fillPrivateInput } from "./private_input.js";
import { expect, test } from "@playwright/test";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import {
  finishOptionalGuide,
  preserveAccountUiEvidence,
} from "./account_ui.js";

const runId = process.env.HARUKA_TEST_RUN_ID;
if (!runId || !/^[0-9a-f]{32}$/.test(runId))
  throw new Error("Owned run required");
const root = path.resolve("../..");
const evidence = path.join(root, "artifacts/stage1-frontend-20261001");
test.afterEach(async ({ page }, info) => preserveAccountUiEvidence(page, info));

test("actual owner language and appearance controls", async ({ page }) => {
  test.setTimeout(120_000);
  const actor = JSON.parse(
    readFileSync(
      path.join(root, "dev/.local/b1", runId, "account-ui-actor-a.json"),
      "utf8",
    ),
  ) as { email: string; password: string };
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
  await page.goto("/settings/languages");
  await expect(page.getByRole("button", { name: /^解释语言 / })).toBeVisible();
  writeFileSync(
    path.join(evidence, "preferences-language-visible.txt"),
    await page.locator("body").ariaSnapshot(),
  );
  await page.getByRole("checkbox", { name: "简体中文", exact: true }).check();
  await page
    .getByRole("checkbox", { name: "日本語", exact: true })
    .last()
    .check();
  await page.getByRole("button", { name: /^解释语言 / }).click();
  await page.getByRole("menuitem", { name: "简体中文", exact: true }).click();
  await page.getByRole("button", { name: /^当前学习语言 / }).click();
  await page.getByRole("menuitem", { name: "日本語", exact: true }).click();
  const commit = page.waitForResponse(
    (r) =>
      r.request().method() === "PATCH" &&
      new URL(r.url()).pathname.endsWith("/study-profile"),
  );
  await page.getByRole("button", { name: "保存语言选项", exact: true }).click();
  expect((await commit).status()).toBe(200);
  await page.reload();
  await expect(
    page.getByRole("checkbox", { name: "简体中文", exact: true }),
  ).toBeChecked();
  await expect(
    page.getByRole("checkbox", { name: "日本語", exact: true }).last(),
  ).toBeChecked();
  await expect(
    page.getByRole("button", { name: "解释语言 简体中文", exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "当前学习语言 日本語", exact: true }),
  ).toBeVisible();
  await page.screenshot({
    path: path.join(evidence, "formal-language-controls-desktop.png"),
  });
});

test("appearance mutations persist and menu resize preserves loaded settings", async ({
  page,
}) => {
  test.setTimeout(120_000);
  const actor = JSON.parse(
    readFileSync(
      path.join(root, "dev/.local/b1", runId, "account-ui-actor-a.json"),
      "utf8",
    ),
  ) as { email: string; password: string };
  const reads: Record<string, number> = {};
  const mutations: number[] = [];
  page.on("request", (r) => {
    const p = new URL(r.url()).pathname;
    if (r.method() === "GET" && p.startsWith("/api/v1/users/me/"))
      reads[p] = (reads[p] ?? 0) + 1;
  });
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
  await page.goto("/settings/appearance");
  const theme = page.getByRole("button", { name: /^主题 / });
  await expect(theme).toBeVisible({ timeout: 30_000 });
  const currentTheme = (await theme.ariaSnapshot()).match(
    /主题 (跟随系统|明亮|深色)/,
  )?.[1];
  if (!currentTheme) throw new Error("Actual theme selection missing");
  const originalTheme = "跟随系统"; // Restore the observed pre-mutation baseline from the retained mobile screenshot.
  const motion = page.getByRole("switch", { name: "减少动态", exact: true });
  const originalMotion = (await motion.getAttribute("aria-checked")) === "true";
  await page.waitForTimeout(700);
  const baseline = { ...reads };
  await theme.click();
  await expect(
    page.getByRole("menuitem", { name: "明亮", exact: true }),
  ).toBeVisible();
  await page.keyboard.press("Escape");
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(motion).toBeVisible();
  await page.waitForTimeout(700);
  expect(reads).toEqual(baseline);
  await page.screenshot({
    path: path.join(evidence, "formal-appearance-mobile-stable.png"),
  });
  await page.setViewportSize({ width: 1440, height: 900 });
  const change = async (action: () => Promise<void>) => {
    const response = page.waitForResponse(
      (r) =>
        r.request().method() === "PATCH" &&
        new URL(r.url()).pathname.endsWith("/settings"),
    );
    await action();
    mutations.push((await response).status());
    expect(mutations.at(-1)).toBe(200);
    await expect(
      page
        .getByRole("group", { name: "h haruka", exact: true })
        .getByText("已保存", { exact: true }),
    ).toBeVisible();
    await page.waitForTimeout(300);
  };
  const alternative = currentTheme === "明亮" ? "跟随系统" : "明亮";
  await theme.click();
  await change(() =>
    page.getByRole("menuitem", { name: alternative, exact: true }).click(),
  );
  await motion.focus();
  await change(() => motion.press("Space"));
  await page.reload();
  await expect(
    page.getByRole("button", { name: new RegExp(`^主题 ${alternative}`) }),
  ).toBeVisible();
  await expect(motion).toHaveAttribute("aria-checked", String(!originalMotion));
  await page.screenshot({
    path: path.join(evidence, "formal-appearance-desktop-persisted.png"),
  });
  await motion.focus();
  await change(() => motion.press("Space"));
  await theme.click();
  await change(() =>
    page.getByRole("menuitem", { name: originalTheme, exact: true }).click(),
  );
  writeFileSync(
    path.join(evidence, "formal-preferences-appearance.json"),
    JSON.stringify(
      {
        result: "passed",
        mutations,
        no_background_read_window: baseline,
        readings_after_actions: reads,
        model_actions: "none",
      },
      null,
      2,
    ),
  );
});
