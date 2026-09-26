import { expect, test } from "@playwright/test";
import { readFileSync } from "node:fs";
import path from "node:path";

const root = path.resolve("../..");
const runId = process.env.HARUKA_TEST_RUN_ID;
if (!runId || !/^[0-9a-f]{32}$/.test(runId)) {
  throw new Error("HARUKA_TEST_RUN_ID must name an isolated run");
}
const runDir = path.join(root, "dev", ".local", "b1", runId);

test("administrator saves registration policy and reads the persisted state", async ({
  page,
}) => {
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
  await expect(id("admin.auth.policy.page")).toBeVisible();

  const toggle = id("admin.auth.policy.registration_toggle");
  const switchNode = async () =>
    (await toggle.locator('[role="switch"]').count())
      ? toggle.locator('[role="switch"]')
      : toggle;
  const currentState = async () => {
    const state = await (await switchNode()).getAttribute("aria-checked");
    expect(["true", "false"]).toContain(state);
    return state === "true";
  };
  const saveAndReadBack = async (enabled: boolean) => {
    if ((await currentState()) !== enabled) await toggle.click();
    const saved = page.waitForResponse(
      (response) =>
        new URL(response.url()).pathname === "/api/v1/admin/auth-policy" &&
        response.request().method() === "PATCH",
    );
    await id("admin.auth.policy.save").click();
    expect((await saved).status()).toBe(200);
    await page.reload();
    await expect(id("admin.auth.policy.page")).toBeVisible();
    expect(await currentState()).toBe(enabled);
  };
  const initialState = await currentState();
  await saveAndReadBack(!initialState);
  await saveAndReadBack(initialState);
});
