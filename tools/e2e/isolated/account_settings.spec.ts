import { fillPrivateInput } from "./private_input.js";
import { expect, test } from "@playwright/test";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import {
  finishOptionalGuide,
  preserveAccountUiEvidence,
} from "./account_ui.js";

const root = path.resolve("../..");
const runId = process.env.HARUKA_TEST_RUN_ID;
if (!runId || !/^[0-9a-f]{32}$/.test(runId))
  throw new Error("An owned isolated run is required");
const runDirectory = path.join(root, "dev", ".local", "b1", runId);
const evidenceDirectory = path.join(root, "artifacts/stage1-frontend-20261001");
let businessEvents: {
  path: string;
  method: string;
  event: string;
  phase: string;
  status?: number;
}[] = [];

test.afterEach(async ({ page }, info) => {
  await preserveAccountUiEvidence(page, info);
  writeFileSync(
    path.join(
      evidenceDirectory,
      `profile-business-events-${Date.now().toString()}.json`,
    ),
    JSON.stringify({ result: info.status, events: businessEvents }, null, 2),
  );
});

test("owner profile optional fields persist and layout/cache dialogs keep existing data", async ({
  page,
}) => {
  test.setTimeout(180_000);
  const actor = JSON.parse(
    readFileSync(path.join(runDirectory, "account-ui-actor-a.json"), "utf8"),
  ) as { email: string; password: string };
  const reads: Record<string, number> = {};
  businessEvents = [];
  let phase = "login";
  const mutations: { path: string; status: number }[] = [];
  const typeProfileField = async (index: number, value: string) => {
    const field = page.getByRole("textbox").nth(index);
    for (let attempt = 0; attempt < 3; attempt++) {
      await field.click();
      await expect(field).toBeFocused();
      await field.press("ControlOrMeta+A");
      await field.press("Backspace");
      if (value) await field.pressSequentially(value, { delay: 60 });
      if ((await field.inputValue()) === value) return;
    }
    throw new Error("Focused profile field did not retain keyboard input");
  };
  let supplierSubmissions = 0;
  page.on("request", (request) => {
    const pathname = new URL(request.url()).pathname;
    if (pathname.startsWith("/api/v1/users/me/")) {
      businessEvents.push({
        path: pathname,
        method: request.method(),
        event: "request",
        phase,
      });
      if (request.method() === "GET")
        reads[pathname] = (reads[pathname] ?? 0) + 1;
    }
    if (
      request.method() === "POST" &&
      /^\/api\/v1\/provider-credentials\/[^/]+\/test$/.test(
        new URL(request.url()).pathname,
      )
    )
      supplierSubmissions++;
  });
  page.on("response", (response) => {
    const pathname = new URL(response.url()).pathname;
    if (!pathname.startsWith("/api/v1/users/me/")) return;
    businessEvents.push({
      path: pathname,
      method: response.request().method(),
      event: "response",
      phase,
      status: response.status(),
    });
    if (response.request().method() !== "GET") {
      mutations.push({ path: pathname, status: response.status() });
    }
  });
  await page.setViewportSize({ width: 1440, height: 900 });
  await test.step("actual actor login and optional guide", async () => {
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
  });
  await test.step("optional profile write and persisted reload", async () => {
    phase = "profile_commit";
    await page.goto("/settings/profile");
    const fields = page.getByRole("textbox");
    await expect(fields.nth(0)).toBeVisible({ timeout: 30_000 });
    await fields.nth(0).click();
    const savedName =
      (await fields.nth(0).inputValue()) === "阶段收口资料样本"
        ? "阶段收口资料样本二"
        : "阶段收口资料样本";
    await typeProfileField(0, savedName);
    await typeProfileField(1, "1990");
    const saved = page.waitForResponse(
      (response) =>
        new URL(response.url()).pathname === "/api/v1/users/me/profile" &&
        response.request().method() === "PATCH",
    );
    await page.getByRole("button", { name: "保存资料", exact: true }).click();
    expect((await saved).status()).toBe(200);
    await page.reload();
    await fields.nth(0).click();
    await expect(fields.nth(0)).toHaveValue(savedName);
    await fields.nth(1).click();
    await expect(fields.nth(1)).toHaveValue("1990");
    await page.screenshot({
      path: path.join(evidenceDirectory, "formal-profile-desktop.png"),
    });
  });
  await test.step("typed draft survives resize without background business reads", async () => {
    phase = "profile_draft_resize";
    const field = page.getByRole("textbox").nth(0);
    await typeProfileField(0, "逐字草稿");
    await expect(field).toBeFocused();
    await page.waitForTimeout(700);
    await expect(field).toBeFocused();
    const previousReads = { ...reads };
    await page.setViewportSize({ width: 390, height: 844 });
    const mobileField = page.getByRole("textbox").nth(0);
    await mobileField.click();
    await expect(mobileField).toHaveValue("逐字草稿");
    await mobileField.press("Tab");
    await page.waitForTimeout(700);
    expect(reads).toEqual(previousReads);
    await page.screenshot({
      path: path.join(evidenceDirectory, "formal-profile-mobile-draft.png"),
    });
  });
  await test.step("optional birth year clears through a real profile commit", async () => {
    phase = "profile_optional_clear";
    await typeProfileField(1, "");
    const saved = page.waitForResponse(
      (response) =>
        new URL(response.url()).pathname === "/api/v1/users/me/profile" &&
        response.request().method() === "PATCH",
    );
    await page.getByRole("button", { name: "保存资料", exact: true }).click();
    expect((await saved).status()).toBe(200);
    await page.reload();
    await page.getByRole("textbox").nth(1).click();
    await expect(page.getByRole("textbox").nth(1)).toHaveValue("");
  });
  await test.step("cache dialog cancellation does not reload existing business data", async () => {
    phase = "cache_initial_navigation";
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.getByRole("button", { name: "本机缓存", exact: true }).click();
    await page.setViewportSize({ width: 390, height: 844 });
    const clear = page.getByText("清除此账号本机缓存", { exact: true });
    await expect(clear).toBeVisible();
    const before = { ...reads };
    phase = "cache_dialog_open";
    await clear.click();
    await expect(page.getByRole("alertdialog")).toBeVisible();
    await expect(
      page.getByRole("group", { name: "清除此账号本机缓存？", exact: true }),
    ).toBeVisible();
    phase = "cache_dialog_cancel";
    await page.getByRole("button", { name: "取消", exact: true }).click();
    await page.waitForTimeout(700);
    expect(reads).toEqual(before);
    await page.screenshot({
      path: path.join(evidenceDirectory, "formal-cache-mobile-cancelled.png"),
    });
  });
  await test.step("Web connection remains the declared same-origin deployment", async () => {
    phase = "web_connection";
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.getByRole("button", { name: "服务连接", exact: true }).click();
    const endpoint = page.getByRole("textbox", {
      name: "Web 使用当前部署，不能在应用内更换服务地址。",
      exact: true,
    });
    await expect(endpoint).toBeVisible();
    await expect(endpoint).toBeDisabled();
    await expect(
      page.getByRole("button", { name: "检查地址", exact: true }),
    ).toHaveCount(0);
    await page.screenshot({
      path: path.join(evidenceDirectory, "formal-web-fixed-endpoint.png"),
    });
  });
  expect(supplierSubmissions).toBe(0);
  writeFileSync(
    path.join(evidenceDirectory, "formal-profile-cache-web.json"),
    JSON.stringify(
      {
        run_id: runId,
        result: "passed",
        observations: [
          "optional_profile_save_reload",
          "optional_birth_year_clear",
          "typed_draft_resize_focus_no_business_reads",
          "cache_dialog_cancel_no_business_reads",
          "web_connection_same_origin",
        ],
        business_gets_by_path: reads,
        mutations,
        supplier_submissions: supplierSubmissions,
        limitations: [
          "avatar, account B isolation, permissions, periodic invalidation, native foreground, theme and language saves require separate evidence",
        ],
      },
      null,
      2,
    ),
  );
});
