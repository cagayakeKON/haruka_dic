import { expect, test } from "@playwright/test";
import { readFileSync } from "node:fs";
import path from "node:path";
import {
  commitPolicyPreview,
  openPolicyEditor,
  preserveAccountUiEvidence,
  selectRegistrationMode,
  type RegistrationMode,
} from "./account_ui.js";

const root = path.resolve("../..");
const runId = process.env.HARUKA_TEST_RUN_ID;
if (!runId || !/^[0-9a-f]{32}$/.test(runId)) {
  throw new Error("HARUKA_TEST_RUN_ID must name an isolated run");
}
const runDir = path.join(root, "dev", ".local", "b1", runId);

test.afterEach(async ({ page }, info) => {
  await preserveAccountUiEvidence(page, info);
});

test("administrator saves registration policy and reads the persisted state", async ({
  page,
}) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  const id = (value: string) => page.getByTestId(value);
  const fillPrivate = async (fieldId: string, value: string) => {
    try {
      const input = id(fieldId).locator("input");
      await input.click();
      await input.fill("");
      await input.pressSequentially(value, { delay: 30 });
      if ((await input.inputValue()) !== value)
        throw new Error("unstable input");
    } catch {
      throw new Error("Administrator input was not retained");
    }
  };
  const adminEmail = `admin-${runId}@haruka.example.test`;
  const adminPassword = readFileSync(
    path.join(runDir, "admin.secret"),
    "utf8",
  ).trim();
  await page.goto("/admin/login");
  await expect(id("admin.auth.login.page")).toBeVisible();
  await fillPrivate("admin.auth.login.email", adminEmail);
  await fillPrivate("admin.auth.login.password", adminPassword);
  const loginResponse = page.waitForResponse(
    (response) =>
      new URL(response.url()).pathname === "/api/v1/admin/auth/login" &&
      response.request().method() === "POST",
  );
  await id("admin.auth.login.submit").click();
  expect((await loginResponse).status()).toBe(200);
  await openPolicyEditor(page);

  const toggle = id("admin.auth.policy.registration_toggle");
  const currentState = async (): Promise<RegistrationMode> => {
    const label = await toggle.innerText();
    if (label.includes("开放注册")) return "open";
    if (label.includes("需审批")) return "approval";
    expect(label).toContain("关闭新注册");
    return "closed";
  };
  const saveAndReadBack = async (mode: RegistrationMode) => {
    await selectRegistrationMode(page, mode);
    await commitPolicyPreview(page);
    await page.reload();
    await expect(toggle).toBeVisible();
    expect(await currentState()).toBe(mode);
  };
  const initialState = await currentState();
  await saveAndReadBack(initialState === "open" ? "closed" : "open");
  await saveAndReadBack(initialState);
});
