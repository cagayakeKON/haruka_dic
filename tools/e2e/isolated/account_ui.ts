import { expect, type Page, type TestInfo } from "@playwright/test";
import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";

export type RegistrationMode = "closed" | "approval" | "open";

const registrationLabels: Record<RegistrationMode, string> = {
  closed: "关闭新注册",
  approval: "需审批",
  open: "开放注册",
};

export async function preserveAccountUiEvidence(
  page: Page,
  info: TestInfo,
): Promise<void> {
  const runId = process.env.HARUKA_TEST_RUN_ID;
  if (!runId || !/^[0-9a-f]{32}$/.test(runId))
    throw new Error("An owned isolated run is required");
  const directory = path.resolve("../../artifacts/stage1-frontend-20261001");
  mkdirSync(directory, { recursive: true });
  const stem = `account-${info.title.replace(/[^a-zA-Z0-9-]+/g, "_")}-${Date.now().toString()}`;
  const screenshot = path.join(directory, `${stem}.png`);
  await page.screenshot({ path: screenshot });
  writeFileSync(
    path.join(directory, `${stem}.json`),
    JSON.stringify(
      {
        run_id: runId,
        result: info.status,
        expected_status: info.expectedStatus,
        test_name: info.title,
        route: new URL(page.url()).pathname,
        viewport: page.viewportSize(),
        screenshot: path.basename(screenshot),
        evidence_layer: "actual_browser_ui_native_test_result",
      },
      null,
      2,
    ),
  );
}

export async function openPolicyEditor(page: Page): Promise<void> {
  await page.getByText("注册策略", { exact: true }).first().click();
  await expect(
    page.getByTestId("admin.auth.policy.registration_toggle"),
  ).toBeVisible();
}

export async function selectRegistrationMode(
  page: Page,
  mode: RegistrationMode,
): Promise<void> {
  const field = page.getByTestId("admin.auth.policy.registration_toggle");
  await field.click();
  await page
    .getByRole("menuitem", { name: registrationLabels[mode], exact: true })
    .click();
  await expect(field).toContainText(registrationLabels[mode]);
}

export async function commitPolicyPreview(page: Page): Promise<void> {
  await page.getByText("预览策略变化", { exact: true }).click();
  await expect(page.getByText("策略变更预览", { exact: true })).toBeVisible();
  const saved = page.waitForResponse(
    (response) =>
      new URL(response.url()).pathname === "/api/v1/admin/auth-policy" &&
      response.request().method() === "PATCH",
  );
  await page.getByTestId("admin.auth.policy.save").click();
  expect((await saved).status()).toBe(200);
}

export async function signOutCurrentAudience(
  page: Page,
  admin = false,
): Promise<void> {
  await page.goto(admin ? "/admin/security" : "/settings/security");
  const signedOut = page.waitForResponse(
    (response) =>
      new URL(response.url()).pathname ===
        (admin ? "/api/v1/admin/auth/logout" : "/api/v1/auth/logout") &&
      response.request().method() === "POST",
  );
  await page
    .getByRole("button", {
      name: admin ? "退出管理端" : "退出登录",
      exact: true,
    })
    .click({ timeout: 30_000 });
  expect((await signedOut).status()).toBe(204);
  await expect(
    page.getByTestId(
      admin ? "admin.auth.login.page" : "client.auth.login.page",
    ),
  ).toBeVisible();
}

export async function finishOptionalGuide(page: Page): Promise<void> {
  const skip = page.getByText("跳过", { exact: true });
  const account = page.getByText("个人资料", { exact: true }).first();
  await expect(skip.or(account).first()).toBeVisible({ timeout: 30_000 });
  if (await skip.isVisible()) await skip.click();
  await expect(account).toBeVisible();
}
