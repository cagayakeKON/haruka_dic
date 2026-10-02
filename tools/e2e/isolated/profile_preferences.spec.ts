import { fillPrivateInput } from "./private_input.js";
import { expect, test, type Page, type Response } from "@playwright/test";
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
const directory = path.join(root, "artifacts/stage1/profile-preferences-ui");
mkdirSync(directory, { recursive: true });
const profilePath = "/api/v1/users/me/profile";
const settingsPath = "/api/v1/users/me/settings";
const genders: Record<string, string> = {
  unspecified: "未填写",
  female: "女",
  male: "男",
  non_binary: "非二元",
  self_described: "自我描述",
  prefer_not_to_say: "不愿说明",
};
const zones: Record<string, string> = {
  "Asia/Tokyo": "东京 / Asia/Tokyo",
  "Asia/Shanghai": "上海 / Asia/Shanghai",
  UTC: "UTC",
};
const display = (mapping: Record<string, string>, value: string): string => {
  const label = mapping[value];
  if (!label) throw new Error("Unregistered display value");
  return label;
};

test.afterEach(async ({ page }, info) => preserveAccountUiEvidence(page, info));

test("actual optional gender timezone and AI demographic consent persist and restore", async ({
  page,
}) => {
  test.setTimeout(180_000);
  const actor = JSON.parse(
    readFileSync(
      path.join(root, "dev/.local/b1", runId, "account-ui-actor-a.json"),
      "utf8",
    ),
  ) as { email: string; password: string };
  const events: { path: string; method: string; status: number }[] = [];
  let supplierSubmissions = 0;
  page.on("response", (response) => {
    const p = new URL(response.url()).pathname;
    if ([profilePath, settingsPath].includes(p))
      events.push({
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
  const wait = (p: string, method = "GET") =>
    page.waitForResponse(
      (r) => new URL(r.url()).pathname === p && r.request().method() === method,
    );
  const data = async (response: Response) => {
    expect(response.status()).toBe(200);
    const envelope = (await response.json()) as {
      data: Record<string, unknown>;
    };
    return envelope.data;
  };
  const select = async (
    target: Page,
    current: string,
    next: string,
    first = false,
  ) => {
    const buttons = target.getByRole("button", { name: current, exact: true });
    await (first ? buttons.first() : buttons.last()).click();
    await target.getByRole("menuitem", { name: next, exact: true }).click();
  };
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
    const initialProfile = wait(profilePath);
    const initialSettings = wait(settingsPath);
    await page.goto("/settings/profile");
    const originalProfile = await data(await initialProfile);
    const originalSettings = await data(await initialSettings);
    const gender = String(originalProfile.gender_code);
    const timezone = originalSettings.timezone as string | null;
    const consent = originalProfile.use_optional_demographics_for_ai === true;
    if (!genders[gender]) throw new Error("Unregistered gender display value");
    const originalZone =
      timezone === null ? "未填写" : (zones[timezone] ?? timezone);
    const nextGender = gender === "female" ? "male" : "female";
    const nextZone = timezone === "Asia/Tokyo" ? "UTC" : "Asia/Tokyo";
    await select(
      page,
      display(genders, gender),
      display(genders, nextGender),
      true,
    );
    await select(page, originalZone, display(zones, nextZone));
    const profileCommit = wait(profilePath, "PATCH");
    const settingsCommit = wait(settingsPath, "PATCH");
    await page.getByRole("button", { name: "保存资料", exact: true }).click();
    expect((await profileCommit).status()).toBe(200);
    expect((await settingsCommit).status()).toBe(200);
    const reloadProfile = wait(profilePath);
    const reloadSettings = wait(settingsPath);
    await page.reload();
    expect((await data(await reloadProfile)).gender_code).toBe(nextGender);
    expect((await data(await reloadSettings)).timezone).toBe(nextZone);
    await expect(
      page.getByRole("button", { name: genders[nextGender], exact: true }),
    ).toBeVisible();
    await expect(
      page.getByRole("button", { name: zones[nextZone], exact: true }),
    ).toBeVisible();
    const consentControl = page.getByRole("switch", {
      name: "允许 AI 使用可选个人资料",
      exact: true,
    });
    await expect(consentControl).toHaveAttribute(
      "aria-checked",
      String(consent),
    );
    const consentCommit = wait(profilePath, "PATCH");
    await consentControl.focus();
    await consentControl.press("Space");
    expect((await consentCommit).status()).toBe(200);
    const consentReload = wait(profilePath);
    await page.reload();
    expect(
      (await data(await consentReload)).use_optional_demographics_for_ai,
    ).toBe(!consent);
    await expect(consentControl).toHaveAttribute(
      "aria-checked",
      String(!consent),
    );
    await page.screenshot({
      path: path.join(directory, "persisted-desktop.png"),
    });
    const consentRestore = wait(profilePath, "PATCH");
    await consentControl.focus();
    await consentControl.press("Space");
    expect((await consentRestore).status()).toBe(200);
    // Reload after the autosave before creating another profile CAS patch.
    const restoredConsent = wait(profilePath);
    await page.reload();
    expect(
      (await data(await restoredConsent)).use_optional_demographics_for_ai,
    ).toBe(consent);
    await select(
      page,
      display(genders, nextGender),
      display(genders, gender),
      true,
    );
    await select(page, display(zones, nextZone), originalZone);
    const restoreProfile = wait(profilePath, "PATCH");
    const restoreSettings = wait(settingsPath, "PATCH");
    await page.getByRole("button", { name: "保存资料", exact: true }).click();
    expect((await restoreProfile).status()).toBe(200);
    expect((await restoreSettings).status()).toBe(200);
    const finalProfile = wait(profilePath);
    const finalSettings = wait(settingsPath);
    await page.reload();
    const final = await data(await finalProfile);
    expect(final.gender_code).toBe(gender);
    expect(final.use_optional_demographics_for_ai).toBe(consent);
    expect((await data(await finalSettings)).timezone).toBe(timezone);
    expect(supplierSubmissions).toBe(0);
  } finally {
    writeFileSync(
      path.join(directory, `events-${Date.now().toString()}.json`),
      JSON.stringify(
        {
          events,
          supplier_submissions: supplierSubmissions,
          evidence:
            "Actual UI mutations and server persistence; no provider call",
        },
        null,
        2,
      ),
    );
  }
});
