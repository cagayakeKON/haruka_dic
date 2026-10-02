import { fillPrivateInput } from "./private_input.js";
import { expect, test } from "@playwright/test";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { preserveAccountUiEvidence } from "./account_ui.js";

const root = path.resolve("../..");
const runId = process.env.HARUKA_TEST_RUN_ID;
if (!runId || !/^[0-9a-f]{32}$/.test(runId))
  throw new Error("Owned run required");
const directory = path.join(root, "artifacts/stage1/admin-protection-ui");
mkdirSync(directory, { recursive: true });
test.afterEach(async ({ page }, info) => preserveAccountUiEvidence(page, info));

test("actual self administration disable is denied and sole admin stays active", async ({
  page,
}) => {
  const email = `admin-${runId}@haruka.example.test`;
  const password = readFileSync(
    path.join(root, "dev/.local/b1", runId, "admin.secret"),
    "utf8",
  ).trim();
  const outcomes: { route: string; method: string; status: number }[] = [];
  page.on("response", (response) => {
    const p = new URL(response.url()).pathname;
    if (p.startsWith("/api/v1/admin/users"))
      outcomes.push({
        route: p.replace(/[0-9a-f]{8}-[0-9a-f-]{27,}/g, "{user_id}"),
        method: response.request().method(),
        status: response.status(),
      });
  });
  const users = () =>
    page.waitForResponse(
      (r) =>
        r.request().method() === "GET" &&
        new URL(r.url()).pathname === "/api/v1/admin/users",
    );
  const owner = async (response: Awaited<ReturnType<typeof users>>) => {
    expect(response.status()).toBe(200);
    const payload = (await response.json()) as {
      data: {
        email: string;
        status: string;
        audiences: string[];
        user_id: string;
        revision: number;
      }[];
    };
    const activeAdmins = payload.data.filter(
      (item) => item.status === "active" && item.audiences.includes("admin"),
    );
    expect(activeAdmins).toHaveLength(1);
    const account = activeAdmins[0];
    if (!account || account.email !== email)
      throw new Error(
        "Owned sole active administrator prerequisite not satisfied",
      );
    return account;
  };
  try {
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto("/admin/login");
    await page
      .getByTestId("admin.auth.login.email")
      .locator("input")
      .fill(email);
    await fillPrivateInput(
      page.getByTestId("admin.auth.login.password").locator("input"),
      password,
    );
    const login = page.waitForResponse(
      (r) =>
        new URL(r.url()).pathname === "/api/v1/admin/auth/login" &&
        r.request().method() === "POST",
    );
    await page.getByTestId("admin.auth.login.submit").click();
    expect((await login).status()).toBe(200);
    // Wait for the real post-login access/session flow before replacing the page.
    await expect(
      page.getByText("注册策略", { exact: true }).first(),
    ).toBeVisible({ timeout: 30_000 });
    const initial = users();
    await page.goto("/admin/users");
    const before = await owner(await initial);
    await page
      .getByRole("row")
      .filter({ hasText: email })
      .getByRole("button", { name: "查看运维摘要", exact: true })
      .click();
    const dialog = page.getByTestId("admin.user.governance.dialog");
    await expect(dialog).toBeVisible();
    const rejected = page.waitForResponse(
      (r) =>
        new URL(r.url()).pathname ===
          `/api/v1/admin/users/${before.user_id}/status` &&
        r.request().method() === "POST",
    );
    await dialog.getByRole("button", { name: "停用", exact: true }).click();
    const refusal = await rejected;
    expect(refusal.status()).toBe(403);
    const error = (await refusal.json()) as { error: { code: string } };
    expect(error.error.code).toBe("PERMISSION_DENIED");
    await expect(
      dialog.getByText("没有操作权限", { exact: true }),
    ).toBeVisible();
    await page.screenshot({
      path: path.join(directory, "self-administration-refused.png"),
    });
    const refreshed = users();
    await page.reload();
    const after = await owner(await refreshed);
    expect(after.user_id).toBe(before.user_id);
    expect(after.revision).toBe(before.revision);
    await expect(page.getByTestId("admin.user.governance.page")).toBeVisible();
  } finally {
    writeFileSync(
      path.join(directory, `events-${Date.now().toString()}.json`),
      JSON.stringify(
        {
          outcomes,
          scope:
            "Sole owned active admin prerequisite, actual UI self-disable attempt, server self-management refusal, unchanged active account after reload; not the last-admin transaction guard; no successful governance mutation",
        },
        null,
        2,
      ),
    );
  }
});
