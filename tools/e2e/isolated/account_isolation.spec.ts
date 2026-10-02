import { fillPrivateInput } from "./private_input.js";
import { expect, test } from "@playwright/test";
import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import path from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import {
  finishOptionalGuide,
  preserveAccountUiEvidence,
  signOutCurrentAudience,
} from "./account_ui.js";

test.afterEach(async ({ page }, info) => preserveAccountUiEvidence(page, info));

test("actual second account has isolated profile and collections and replaces old account content", async ({
  page,
}) => {
  test.setTimeout(180_000);
  const root = path.resolve("../..");
  const runId = process.env.HARUKA_TEST_RUN_ID;
  if (!runId || !/^[0-9a-f]{32}$/.test(runId))
    throw new Error("Owned run required");
  const directory = path.join(root, "dev/.local/b1", runId);
  const actorA = JSON.parse(
    readFileSync(path.join(directory, "account-ui-actor-a.json"), "utf8"),
  ) as { email: string; password: string };
  const bFile = path.join(directory, "account-ui-actor-b.json");
  const actorB = existsSync(bFile)
    ? (JSON.parse(readFileSync(bFile, "utf8")) as {
        email: string;
        password: string;
      })
    : {
        email: `isolation-${randomBytes(8).toString("hex")}@haruka.example.test`,
        password: `Valid-${randomBytes(12).toString("hex")}`,
      };
  const collection = JSON.parse(
    readFileSync(
      path.join(
        root,
        "artifacts/stage1-frontend-20261001/formal-collection-owner.json",
      ),
      "utf8",
    ),
  ) as { collection_id: string };
  let modelSubmissions = 0;
  page.on("request", (r) => {
    if (
      r.method() === "POST" &&
      /\/provider-credentials\/[^/]+\/test$/.test(new URL(r.url()).pathname)
    )
      modelSubmissions++;
  });
  const login = async (actor: { email: string; password: string }) => {
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
  };
  await login(actorA);
  await page.goto("/settings/profile");
  const name = page.getByRole("textbox").nth(0);
  await name.click();
  const aName = await name.inputValue();
  await page.goto("/collections");
  const oldRow = page.getByTestId(
    `client.reference.collections.row.${collection.collection_id}`,
  );
  await expect(oldRow).toBeVisible({ timeout: 30_000 });
  const oldTab = await page.context().newPage();
  await oldTab.goto("/collections");
  await expect(
    oldTab.getByTestId(
      `client.reference.collections.row.${collection.collection_id}`,
    ),
  ).toBeVisible({ timeout: 30_000 });
  try {
    await signOutCurrentAudience(page);
    if (!existsSync(bFile)) {
      await page.goto("/register");
      await fillPrivateInput(
        page.getByTestId("client.auth.register.email").locator("input"),
        actorB.email,
      );
      await fillPrivateInput(
        page.getByTestId("client.auth.register.password").locator("input"),
        actorB.password,
      );
      await fillPrivateInput(
        page.getByTestId("client.auth.register.confirm").locator("input"),
        actorB.password,
      );
      const accepted = page.waitForResponse(
        (r) =>
          new URL(r.url()).pathname === "/api/v1/auth/register" &&
          r.request().method() === "POST",
      );
      await page.getByTestId("client.auth.register.submit").click();
      expect((await accepted).status()).toBe(202);
      await expect(page.getByTestId("client.auth.result.page")).toBeVisible();
      const output = path.join(
        directory,
        "mail",
        `isolation-${randomBytes(8).toString("hex")}.link`,
      );
      let link = "";
      for (let attempt = 0; attempt < 30; attempt++) {
        try {
          execFileSync(
            path.join(root, "backend/.venv/Scripts/python.exe"),
            [
              "-m",
              "dev.local_smtp_capture",
              "extract",
              "--spool",
              path.join(directory, "mail"),
              "--recipient",
              actorB.email,
              "--purpose",
              "verify",
              "--output",
              output,
            ],
            { cwd: root, stdio: "pipe" },
          );
          link = readFileSync(output, "utf8").trim();
          unlinkSync(output);
          break;
        } catch {
          await delay(1000);
        }
      }
      if (!link) throw new Error("Owned verification mail not received");
      try {
        await page.goto(link);
      } catch {
        throw new Error("Owned verification navigation failed");
      }
      await expect(
        page.getByTestId("client.auth.verification.page"),
      ).toBeVisible();
      const verified = page.waitForResponse(
        (r) =>
          new URL(r.url()).pathname === "/api/v1/auth/email/verify" &&
          r.request().method() === "POST",
      );
      await page.getByTestId("client.auth.verification.submit").click();
      expect((await verified).status()).toBe(204);
      writeFileSync(bFile, JSON.stringify(actorB));
    }
    await login(actorB);
    await page.goto("/collections");
    await expect(
      page.getByTestId("client.reference.collections.page"),
    ).toBeVisible({ timeout: 30_000 });
    await expect(oldRow).toHaveCount(0);
    await expect(
      oldTab.getByTestId(
        `client.reference.collections.row.${collection.collection_id}`,
      ),
    ).toHaveCount(0);
    await page.goto("/settings/profile");
    await name.click();
    expect(await name.inputValue()).toBe("");
    await name.pressSequentially("隔离用户 B", { delay: 60 });
    const saved = page.waitForResponse(
      (r) =>
        new URL(r.url()).pathname === "/api/v1/users/me/profile" &&
        r.request().method() === "PATCH",
    );
    await page.getByRole("button", { name: "保存资料", exact: true }).click();
    expect((await saved).status()).toBe(200);
    await signOutCurrentAudience(page);
    await login(actorA);
    await page.goto("/settings/profile");
    await name.click();
    expect(await name.inputValue()).toBe(aName);
    expect(modelSubmissions).toBe(0);
    writeFileSync(
      path.join(
        root,
        "artifacts/stage1-frontend-20261001/formal-account-isolation.json",
      ),
      JSON.stringify(
        {
          run_id: runId,
          result: "passed",
          steps: [
            "B actual registration and email verification or verified actor reuse",
            "A persisted collection absent for B",
            "old A tab removes collection on auth scope change",
            "B optional profile starts empty and saves via PATCH200",
            "A profile unchanged after B save and switch back",
          ],
          model_submissions: modelSubmissions,
        },
        null,
        2,
      ),
    );
  } finally {
    await oldTab.close();
  }
});
