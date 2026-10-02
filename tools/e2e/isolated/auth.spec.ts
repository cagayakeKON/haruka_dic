import { expect, test } from "@playwright/test";
import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { readFileSync, unlinkSync, writeFileSync } from "node:fs";
import path from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import {
  commitPolicyPreview,
  finishOptionalGuide,
  openPolicyEditor,
  preserveAccountUiEvidence,
  selectRegistrationMode,
  signOutCurrentAudience,
} from "./account_ui.js";

const root = path.resolve("../..");
const runId = process.env.HARUKA_TEST_RUN_ID;
if (!runId || !/^[0-9a-f]{32}$/.test(runId)) {
  throw new Error("HARUKA_TEST_RUN_ID must name an isolated run");
}
const runDir = path.join(root, "dev", ".local", "b1", runId);
const python = path.join(root, "backend", ".venv", "Scripts", "python.exe");

test.afterEach(async ({ page }, info) => {
  await preserveAccountUiEvidence(page, info);
});

async function privateMailLink(
  recipient: string,
  purpose: "verify" | "reset",
): Promise<string> {
  const output = path.join(
    runDir,
    "mail",
    `ui-${randomBytes(8).toString("hex")}.link`,
  );
  for (let attempt = 0; attempt < 30; attempt++) {
    try {
      execFileSync(
        python,
        [
          "-m",
          "dev.local_smtp_capture",
          "extract",
          "--spool",
          path.join(runDir, "mail"),
          "--recipient",
          recipient,
          "--purpose",
          purpose,
          "--output",
          output,
        ],
        { cwd: root, stdio: "pipe" },
      );
      const link = readFileSync(output, "utf8").trim();
      unlinkSync(output);
      return link;
    } catch {
      await delay(1000);
    }
  }
  throw new Error("No isolated mail action link arrived");
}

test("administrator opens registration and a user verifies email before login", async ({
  page,
}) => {
  test.setTimeout(360_000);
  await page.setViewportSize({ width: 1440, height: 900 });
  const id = (value: string) => page.getByTestId(value);
  const input = (value: string) => id(value).locator("input, textarea");
  const fillPrivate = async (fieldId: string, value: string) => {
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        await input(fieldId).click();
        await input(fieldId).fill("");
        await input(fieldId).pressSequentially(value, { delay: 40 });
        if ((await input(fieldId).inputValue()) === value) return;
      } catch {
        // A route or semantics rebuild can interrupt a focused field.
      }
    }
    throw new Error(`Private field ${fieldId} could not be filled`);
  };
  const adminEmail = `admin-${runId}@haruka.example.test`;
  const adminPassword = readFileSync(
    path.join(runDir, "admin.secret"),
    "utf8",
  ).trim();
  await page.goto("/admin/login");
  await expect(id("admin.auth.login.page")).toBeVisible({ timeout: 30_000 });
  await fillPrivate("admin.auth.login.email", adminEmail);
  await fillPrivate("admin.auth.login.password", adminPassword);
  await id("admin.auth.login.submit").click();
  await openPolicyEditor(page);
  const registrationToggle = id("admin.auth.policy.registration_toggle");
  if (!(await registrationToggle.innerText()).includes("开放注册")) {
    await selectRegistrationMode(page, "open");
    await commitPolicyPreview(page);
  }
  await signOutCurrentAudience(page, true);

  const email = `learner-${randomBytes(8).toString("hex")}@haruka.example.test`;
  const password = `Valid-${randomBytes(12).toString("hex")}`;
  await page.goto("/register");
  await expect(id("client.auth.register.page")).toBeVisible({
    timeout: 30_000,
  });
  await fillPrivate("client.auth.register.email", email);
  await fillPrivate("client.auth.register.confirm", password);
  await fillPrivate("client.auth.register.password", password);
  if (
    (await input("client.auth.register.password").inputValue()) !== password ||
    (await input("client.auth.register.confirm").inputValue()) !== password
  ) {
    throw new Error("Registration input did not remain stable");
  }
  await id("client.auth.register.submit").click();
  await expect(id("client.auth.result.page")).toBeVisible();

  const link = await privateMailLink(email, "verify");
  try {
    await page.goto(link);
  } catch {
    throw new Error("Isolated verification navigation failed");
  }
  await expect(id("client.auth.verification.page")).toBeVisible();
  expect(page.url().includes("token=")).toBe(false);
  await id("client.auth.verification.submit").click();
  await expect(id("client.auth.result.page")).toBeVisible();

  await page.goto("/login");
  await expect(id("client.auth.login.page")).toBeVisible({ timeout: 30_000 });
  await fillPrivate("client.auth.login.email", email);
  await fillPrivate("client.auth.login.password", password);
  if (
    (await input("client.auth.login.email").inputValue()) !== email ||
    (await input("client.auth.login.password").inputValue()) !== password
  ) {
    throw new Error("Login input did not remain stable");
  }
  const firstLogin = page.waitForResponse(
    (response) =>
      new URL(response.url()).pathname === "/api/v1/auth/login" &&
      response.request().method() === "POST",
    { timeout: 30_000 },
  );
  await id("client.auth.login.submit").click();
  expect((await firstLogin).status()).toBe(200);
  writeFileSync(
    path.join(runDir, "account-ui-actor-a.json"),
    JSON.stringify({ email, password }),
  );
  await finishOptionalGuide(page);

  await signOutCurrentAudience(page);
  await id("client.auth.login.recovery_link").click();
  await expect(id("client.auth.recovery_request.page")).toBeVisible();
  await fillPrivate("client.auth.recovery_request.email", email);
  const recoveryAccepted = page.waitForResponse(
    (response) =>
      new URL(response.url()).pathname === "/api/v1/auth/recovery/request" &&
      response.request().method() === "POST",
    { timeout: 30_000 },
  );
  await id("client.auth.recovery_request.submit").click();
  expect((await recoveryAccepted).status()).toBe(202);
  await expect(id("client.auth.result.page")).toBeVisible({ timeout: 30_000 });

  const resetLink = await privateMailLink(email, "reset");
  let resetSubmissions = 0;
  page.on("request", (request) => {
    if (
      new URL(request.url()).pathname === "/api/v1/auth/recovery/complete" &&
      request.method() === "POST"
    ) {
      resetSubmissions++;
    }
  });
  try {
    await page.goto(resetLink);
  } catch {
    throw new Error("Isolated recovery navigation failed");
  }
  await expect(id("client.auth.recovery_complete.page")).toBeVisible();
  expect(page.url().includes("token=")).toBe(false);
  expect(resetSubmissions).toBe(0);
  const newPassword = `Reset-${randomBytes(12).toString("hex")}`;
  await fillPrivate("client.auth.recovery_complete.password", newPassword);
  await fillPrivate("client.auth.recovery_complete.confirm", newPassword);
  await id("client.auth.recovery_complete.submit").click();
  await expect(id("client.auth.result.page")).toBeVisible();
  expect(resetSubmissions).toBe(1);
  await page.goto("/login");
  await expect(id("client.auth.login.page")).toBeVisible({ timeout: 30_000 });
  await fillPrivate("client.auth.login.email", email);
  await fillPrivate("client.auth.login.password", newPassword);
  if (
    (await input("client.auth.login.email").inputValue()) !== email ||
    (await input("client.auth.login.password").inputValue()) !== newPassword
  ) {
    throw new Error("Login input did not remain stable");
  }
  const secondLogin = page.waitForResponse(
    (response) =>
      new URL(response.url()).pathname === "/api/v1/auth/login" &&
      response.request().method() === "POST",
    { timeout: 30_000 },
  );
  await id("client.auth.login.submit").click();
  expect((await secondLogin).status()).toBe(200);
  await finishOptionalGuide(page);
  writeFileSync(
    path.join(runDir, "account-ui-actor-a.json"),
    JSON.stringify({ email, password: newPassword }),
  );
});
