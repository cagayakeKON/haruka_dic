import { expect, test } from "@playwright/test";
import { execFileSync } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import { readFileSync, unlinkSync, writeFileSync } from "node:fs";
import path from "node:path";
import { setTimeout as delay } from "node:timers/promises";

const root = path.resolve("../..");
const runId = process.env.HARUKA_TEST_RUN_ID;
if (!runId || !/^[0-9a-f]{32}$/.test(runId)) {
  throw new Error("HARUKA_TEST_RUN_ID must name an isolated run");
}
const runDir = path.join(root, "dev", ".local", "b1", runId);
const python = path.join(root, "backend", ".venv", "Scripts", "python.exe");
const uuidV4 =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

async function verificationLink(recipient: string): Promise<string> {
  const output = path.join(
    runDir,
    "mail",
    `reference-${randomBytes(8).toString("hex")}.link`,
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
          "verify",
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
  throw new Error("Isolated verification message did not arrive");
}

test("selected source resolves a persisted card and its collection stays private after account switch", async ({
  page,
}) => {
  const id = (value: string) => page.getByTestId(value);
  const fillPrivate = async (fieldId: string, value: string) => {
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const input = id(fieldId).locator("input");
        await input.click();
        await input.fill("");
        await input.pressSequentially(value, { delay: 30 });
        if ((await input.inputValue()) === value) return;
      } catch {
        // A route rebuild can replace Flutter's active editing node.
      }
    }
    throw new Error("Private field could not be entered");
  };
  const registerAndLogin = async (email: string, password: string) => {
    await page.goto("/register");
    await expect(id("client.auth.register.page")).toBeVisible();
    await fillPrivate("client.auth.register.email", email);
    await fillPrivate("client.auth.register.confirm", password);
    await fillPrivate("client.auth.register.password", password);
    const accepted = page.waitForResponse(
      (response) =>
        new URL(response.url()).pathname === "/api/v1/auth/register" &&
        response.request().method() === "POST",
    );
    await id("client.auth.register.submit").click();
    expect((await accepted).status()).toBe(202);
    await expect(id("client.auth.result.page")).toBeVisible();
    const link = await verificationLink(email);
    try {
      await page.goto(link);
    } catch {
      throw new Error("Verification navigation failed");
    }
    await expect(id("client.auth.verification.page")).toBeVisible();
    expect(page.url().includes("token=")).toBe(false);
    const verified = page.waitForResponse(
      (response) =>
        new URL(response.url()).pathname === "/api/v1/auth/email/verify" &&
        response.request().method() === "POST",
    );
    await id("client.auth.verification.submit").click();
    expect((await verified).status()).toBe(204);
    await page.goto("/login");
    await expect(id("client.auth.login.page")).toBeVisible();
    await fillPrivate("client.auth.login.email", email);
    await fillPrivate("client.auth.login.password", password);
    const login = page.waitForResponse(
      (response) =>
        new URL(response.url()).pathname === "/api/v1/auth/login" &&
        response.request().method() === "POST",
    );
    await id("client.auth.login.submit").click();
    expect((await login).status()).toBe(200);
    await expect(id("client.account.home.page")).toBeVisible();
  };

  // Registration policy is changed through the real administrator UI.
  const adminEmail = `admin-${runId}@haruka.example.test`;
  const adminPassword = readFileSync(
    path.join(runDir, "admin.secret"),
    "utf8",
  ).trim();
  await page.goto("/admin/login");
  await expect(id("admin.auth.login.page")).toBeVisible();
  await fillPrivate("admin.auth.login.email", adminEmail);
  await fillPrivate("admin.auth.login.password", adminPassword);
  await id("admin.auth.login.submit").click();
  await expect(id("admin.auth.policy.page")).toBeVisible();
  const registration = id("admin.auth.policy.registration_toggle");
  const switchNode = (await registration.locator('[role="switch"]').count())
    ? registration.locator('[role="switch"]')
    : registration;
  if ((await switchNode.getAttribute("aria-checked")) === "false") {
    await registration.click();
    const saved = page.waitForResponse(
      (response) =>
        new URL(response.url()).pathname === "/api/v1/admin/auth-policy" &&
        response.request().method() === "PATCH",
    );
    await id("admin.auth.policy.save").click();
    expect((await saved).status()).toBe(200);
  }
  await id("admin.auth.policy.sign_out").click();
  await expect(id("admin.auth.login.page")).toBeVisible();

  const firstEmail = `source-${randomBytes(8).toString("hex")}@haruka.example.test`;
  const firstPassword = `Valid-${randomBytes(12).toString("hex")}`;
  await registerAndLogin(firstEmail, firstPassword);
  try {
    execFileSync(
      python,
      [
        "-m",
        "dev.isolated_app_run",
        "seed-source",
        "--run-id",
        runId,
        "--owner-email",
        firstEmail,
      ],
      {
        cwd: root,
        stdio: "pipe",
        env: Object.fromEntries(
          Object.entries(process.env).filter(([key]) => !/^HARUKA_/i.test(key)),
        ),
      },
    );
  } catch {
    throw new Error("Controlled source preparation failed");
  }
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto("/reference/materials");
  await expect(id("client.reference.materials.page")).toBeVisible();
  const materialRow = page.locator(
    '[flt-semantics-identifier^="client.reference.materials.row."]',
  );
  await expect(materialRow).toHaveCount(1);
  await materialRow.click();
  const block = page.locator(
    '[flt-semantics-identifier^="client.reference.chapter.block."]',
  );
  await expect(block).toHaveCount(1);
  await page.waitForTimeout(500);
  const bounds = await block.boundingBox();
  if (!bounds) throw new Error("Published text has no visible bounds");
  const y = bounds.y + bounds.height / 2;
  let selected = "";
  // Canvas glyph metrics vary with the installed font. Every attempt is an
  // ordinary pointer drag on the visible source, followed by a read-only check.
  for (const start of [32, 37, 27, 42]) {
    await page.mouse.click(bounds.x + 160, y);
    await page.mouse.move(bounds.x + start, y);
    await page.mouse.down();
    await page.waitForTimeout(750);
    await page.mouse.move(bounds.x + start + 20, y, { steps: 8 });
    await page.mouse.up();
    selected = await page.evaluate(
      () => window.getSelection()?.toString() ?? "",
    );
    if (selected === "空") break;
  }
  if (selected !== "空") {
    throw new Error("Real text drag did not select the published word");
  }
  const resolved = page.waitForResponse(
    (response) =>
      new URL(response.url()).pathname === "/api/v1/explanations/resolve" &&
      response.request().method() === "POST",
  );
  await id("client.reference.selection.query").click();
  expect((await resolved).status()).toBe(200);
  await expect(id("client.reference.collection.save")).toBeVisible();
  const created = page.waitForResponse(
    (response) =>
      new URL(response.url()).pathname === "/api/v1/collections" &&
      response.request().method() === "POST",
  );
  await id("client.reference.collection.save").click();
  const createResponse = await created;
  expect(createResponse.status()).toBe(201);
  const headers = createResponse.request().headers();
  expect(uuidV4.test(headers["x-operation-id"] ?? "")).toBe(true);
  expect(uuidV4.test(headers["idempotency-key"] ?? "")).toBe(true);
  expect(headers["x-operation-id"] === headers["idempotency-key"]).toBe(true);
  const saved = (await createResponse.json()) as { data?: { id?: string } };
  const collectionId = saved.data?.id;
  if (!collectionId || !uuidV4.test(collectionId)) {
    throw new Error("Collection response omitted its stable ID");
  }
  await expect(id("client.reference.collection.saved_state")).toBeVisible();
  await page.goto("/collections");
  await expect(id("client.reference.collections.loaded")).toBeVisible();
  await expect(
    id(`client.reference.collections.row.${collectionId}`),
  ).toBeVisible();
  await page.reload();
  await expect(id("client.reference.collections.loaded")).toBeVisible();
  await expect(
    id(`client.reference.collections.row.${collectionId}`),
  ).toBeVisible();

  const otherTab = await page.context().newPage();
  const otherTabId = (value: string) => otherTab.getByTestId(value);
  await otherTab.goto("/collections");
  await expect(otherTabId("client.reference.collections.loaded")).toBeVisible();
  await expect(
    otherTabId(`client.reference.collections.row.${collectionId}`),
  ).toBeVisible();

  await page.goto("/account");
  await expect(id("client.account.home.page")).toBeVisible();
  await id("client.account.home.sign_out").click();
  await expect(id("client.auth.login.page")).toBeVisible();
  await expect(otherTabId("client.shell.not_found.page")).toBeVisible({
    timeout: 15_000,
  });
  await expect(
    otherTabId(`client.reference.collections.row.${collectionId}`),
  ).toHaveCount(0);
  const secondEmail = `source-${randomBytes(8).toString("hex")}@haruka.example.test`;
  const secondPassword = `Valid-${randomBytes(12).toString("hex")}`;
  await registerAndLogin(secondEmail, secondPassword);
  await page.goto("/collections");
  await expect(id("client.reference.collections.loaded")).toBeVisible();
  await expect(
    id(`client.reference.collections.row.${collectionId}`),
  ).toHaveCount(0);
  await expect(otherTabId("client.reference.collections.loaded")).toBeVisible({
    timeout: 15_000,
  });
  await expect(
    otherTabId(`client.reference.collections.row.${collectionId}`),
  ).toHaveCount(0);
  await otherTab.reload();
  await expect(otherTabId("client.reference.collections.loaded")).toBeVisible();
  await expect(
    otherTabId(`client.reference.collections.row.${collectionId}`),
  ).toHaveCount(0);
  await otherTab.close();

  const bundle = readFileSync(path.join(runDir, "web", "main.dart.js"));
  const proofPath = path.join(
    runDir,
    `web-reference-proof-${randomBytes(8).toString("hex")}.json`,
  );
  writeFileSync(
    proofPath,
    JSON.stringify(
      {
        result: "passed",
        evidence_layer: "browser_ui_and_http",
        pg_single_row_checked: false,
        run_id: runId,
        web_bundle_sha256: createHash("sha256").update(bundle).digest("hex"),
        registration_status: 202,
        verification_status: 204,
        login_status: 200,
        resolve_status: 200,
        create_status: 201,
        collection_id: collectionId,
        same_id_after_reload: true,
        absent_after_account_switch: true,
        absent_in_other_tab_after_sign_out_and_account_switch: true,
        collection_operation_matches_idempotency: true,
      },
      null,
      2,
    ),
    { flag: "wx" },
  );
});
