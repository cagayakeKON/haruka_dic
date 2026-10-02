import { fillPrivateInput } from "./private_input.js";
import { expect, test } from "@playwright/test";
import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import {
  finishOptionalGuide,
  preserveAccountUiEvidence,
  signOutCurrentAudience,
} from "./account_ui.js";

test.afterEach(async ({ page }, info) => preserveAccountUiEvidence(page, info));

test("owner uploads a fixed avatar through the picker and account switch clears the old image", async ({
  page,
}) => {
  test.setTimeout(150_000);
  const root = path.resolve("../..");
  const runId = process.env.HARUKA_TEST_RUN_ID;
  if (!runId || !/^[0-9a-f]{32}$/.test(runId))
    throw new Error("Owned run required");
  const directory = path.join(root, "dev/.local/b1", runId);
  const actor = (letter: string) =>
    JSON.parse(
      readFileSync(
        path.join(directory, `account-ui-actor-${letter}.json`),
        "utf8",
      ),
    ) as { email: string; password: string };
  const login = async (letter: string) => {
    const a = actor(letter);
    await page.goto("/login");
    await fillPrivateInput(
      page.getByTestId("client.auth.login.email").locator("input"),
      a.email,
    );
    await fillPrivateInput(
      page.getByTestId("client.auth.login.password").locator("input"),
      a.password,
    );
    await page.getByTestId("client.auth.login.submit").click();
    await finishOptionalGuide(page);
  };
  let modelTests = 0;
  page.on("request", (r) => {
    if (
      r.method() === "POST" &&
      /\/provider-credentials\/[^/]+\/test$/.test(new URL(r.url()).pathname)
    )
      modelTests++;
  });
  await login("a");
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto("/settings/profile");
  const replace = page.getByRole("button", { name: "更换头像", exact: true });
  await expect(replace).toBeVisible({ timeout: 30_000 });
  const chooser = page.waitForEvent("filechooser");
  const intent = page.waitForResponse(
    (r) =>
      new URL(r.url()).pathname === "/api/v1/users/me/avatar-upload-intents" &&
      r.request().method() === "POST",
  );
  const complete = page.waitForResponse(
    (r) =>
      /\/api\/v1\/users\/me\/avatar-upload-intents\/[^/]+\/complete$/.test(
        new URL(r.url()).pathname,
      ) && r.request().method() === "POST",
  );
  const media = page.waitForResponse(
    (r) =>
      new URL(r.url()).pathname === "/api/v1/users/me/avatar" &&
      r.request().method() === "GET" &&
      r.status() === 200,
  );
  await replace.click();
  await (
    await chooser
  ).setFiles(path.join(root, "frontend/test/fixtures/preview/query_image.png"));
  expect((await intent).status()).toBe(200);
  expect((await complete).status()).toBe(200);
  const privateRead = await media;
  expect((await privateRead.allHeaders())["cache-control"]).toContain(
    "private, no-store",
  );
  await expect(
    page.getByRole("button", { name: "删除头像", exact: true }),
  ).toBeVisible();
  await page.screenshot({
    path: path.join(
      root,
      "artifacts/stage1-frontend-20261001/formal-avatar-owner-desktop.png",
    ),
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({
    path: path.join(
      root,
      "artifacts/stage1-frontend-20261001/formal-avatar-owner-mobile.png",
    ),
  });
  await signOutCurrentAudience(page);
  await page.setViewportSize({ width: 1440, height: 900 });
  await login("b");
  const profileRead = page.waitForResponse(
    (r) =>
      new URL(r.url()).pathname === "/api/v1/users/me/profile" &&
      r.request().method() === "GET",
  );
  await page.goto("/settings/profile");
  const profile = (await (await profileRead).json()) as {
    data: { avatar_asset_id: string | null };
  };
  expect(profile.data.avatar_asset_id).toBeNull();
  await expect(
    page.getByRole("button", { name: "更换头像", exact: true }),
  ).toBeVisible({ timeout: 30_000 });
  await expect(
    page.getByRole("button", { name: "删除头像", exact: true }),
  ).toHaveCount(0);
  await page.screenshot({
    path: path.join(
      root,
      "artifacts/stage1-frontend-20261001/formal-avatar-account-b-cleared.png",
    ),
  });
  expect(modelTests).toBe(0);
  writeFileSync(
    path.join(
      root,
      "artifacts/stage1-frontend-20261001/formal-avatar-owner.json",
    ),
    JSON.stringify(
      {
        run_id: runId,
        result: "passed",
        steps: [
          "actual file picker submits canonical PNG fixture",
          "intent200 complete200 and owner private image GET200",
          "private no-store header",
          "same browser A to B returns null avatar and no old-image delete control",
        ],
        credential_test_posts: modelTests,
        limitations: [
          "not a broad supplier-attempt count",
          "invalid formats/resource attacks/late races require host evidence",
          "avatar cancellation and permission revocation separate",
        ],
      },
      null,
      2,
    ),
  );
});
