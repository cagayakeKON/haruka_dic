import { expect, test } from "@playwright/test";
import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import {
  existsSync,
  readFileSync,
  readdirSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import path from "node:path";
import { setTimeout as delay } from "node:timers/promises";

const root = path.resolve("../..");
const runId = process.env.HARUKA_TEST_RUN_ID;
if (!runId || !/^[0-9a-f]{32}$/.test(runId)) {
  throw new Error("HARUKA_TEST_RUN_ID must name an isolated run");
}
const runDir = path.join(root, "dev", ".local", "b1", runId);
const python = path.join(root, "backend", ".venv", "Scripts", "python.exe");
const uuid4 =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

function eventIds(body: string | null): string[] {
  try {
    const document = JSON.parse(body ?? "") as {
      events?: { event_id?: unknown }[];
    };
    if (
      !Array.isArray(document.events) ||
      document.events.length === 0 ||
      document.events.length > 20
    ) {
      throw new Error("Invalid batch");
    }
    const ids = document.events.map((event) => event.event_id);
    if (ids.some((value) => typeof value !== "string" || !uuid4.test(value))) {
      throw new Error("Invalid identity");
    }
    return ids as string[];
  } catch {
    // Do not include a telemetry body in test output; it may contain private data.
    throw new Error(
      "Authenticated telemetry request lacks valid event identities",
    );
  }
}

async function privateMailLink(recipient: string): Promise<string> {
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
  throw new Error("No isolated verification mail arrived");
}

test("authenticated Web telemetry recovers the same event after receiver 503", async ({
  page,
}) => {
  test.setTimeout(120_000);
  const id = (value: string) => page.getByTestId(value);
  const fillPrivate = async (fieldId: string, value: string, target = page) => {
    const field = target.getByTestId(fieldId).locator("input");
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        await field.click();
        await field.fill("");
        await field.pressSequentially(value, { delay: 30 });
        if ((await field.inputValue()) === value) return;
      } catch {
        // A Flutter route rebuild can interrupt a focused field.
      }
    }
    throw new Error(`Private field ${fieldId} could not be filled`);
  };
  // Provision a Web-only actor through the real registration and local-mail UI.
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
  const registrationToggle = id("admin.auth.policy.registration_toggle");
  const switchNode = registrationToggle.locator('[role="switch"]');
  const switchState = await ((await switchNode.count())
    ? switchNode.getAttribute("aria-checked")
    : registrationToggle.getAttribute("aria-checked"));
  if (switchState !== "true" && switchState !== "false") {
    throw new Error("Registration policy state unavailable");
  }
  try {
    if (switchState === "false") {
      await registrationToggle.click();
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

    const email = `telemetry-${randomBytes(8).toString("hex")}@haruka.example.test`;
    const password = `Valid-${randomBytes(12).toString("hex")}`;
    await page.goto("/register");
    await expect(id("client.auth.register.page")).toBeVisible();
    await fillPrivate("client.auth.register.email", email);
    await fillPrivate("client.auth.register.confirm", password);
    await fillPrivate("client.auth.register.password", password);
    await id("client.auth.register.submit").click();
    await expect(id("client.auth.result.page")).toBeVisible();
    const verificationLink = await privateMailLink(email);
    try {
      await page.goto(verificationLink);
    } catch {
      throw new Error("Isolated verification navigation failed");
    }
    await expect(id("client.auth.verification.page")).toBeVisible();
    await id("client.auth.verification.submit").click();
    await expect(id("client.auth.result.page")).toBeVisible();
    await page.goto("/login");
    await expect(id("client.auth.login.page")).toBeVisible();
    await fillPrivate("client.auth.login.email", email);
    await fillPrivate("client.auth.login.password", password);

    const ruleId = execFileSync(
      python,
      [
        "-m",
        "dev.local_api_fault_proxy",
        "arm",
        "--run-id",
        runId,
        "--mode",
        "before_503",
        "--method",
        "POST",
        "--path",
        "/api/v1/frontend-logs",
        "--duration-seconds",
        "120",
      ],
      { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
    ).trim();
    if (!/^[0-9a-f]{32}$/.test(ruleId)) {
      throw new Error("Fault proxy did not return a safe rule identity");
    }
    try {
      const firstFailure = page.waitForResponse(
        (response) =>
          new URL(response.url()).pathname === "/api/v1/frontend-logs" &&
          response.request().method() === "POST" &&
          response.status() === 503,
        { timeout: 45_000 },
      );
      const recovered = page.waitForResponse(
        (response) =>
          new URL(response.url()).pathname === "/api/v1/frontend-logs" &&
          response.request().method() === "POST" &&
          response.status() === 200,
        { timeout: 45_000 },
      );
      await id("client.auth.login.submit").click();
      await expect(id("client.account.home.page")).toBeVisible({
        timeout: 30_000,
      });
      const access = await page.request.get("/api/v1/me/access");
      expect(access.status()).toBe(200);
      const accessBody = (await access.json()) as {
        data?: { user_id?: string };
      };
      const userId = accessBody.data?.user_id;
      if (!userId || !/^[0-9a-f-]{36}$/.test(userId)) {
        throw new Error("Authenticated access omitted the owner identity");
      }
      await id("client.shell.reference.collections").click();
      await expect(id("client.reference.collections.loaded")).toBeVisible();
      const failedResponse = await firstFailure;
      const recoveredResponse = await recovered;
      const failedIds = eventIds(failedResponse.request().postData());
      const recoveredIds = eventIds(recoveredResponse.request().postData());
      const retriedIds = failedIds.filter((value) =>
        recoveredIds.includes(value),
      );
      if (retriedIds.length === 0) {
        throw new Error(
          "Receiver recovery did not retry a failed event identity",
        );
      }
      const batchBody = (await recoveredResponse.json()) as {
        data?: { results?: { event_id?: string; status?: string }[] };
      };
      const results = batchBody.data?.results;
      if (
        !Array.isArray(results) ||
        retriedIds.some(
          (eventId) =>
            !results.some(
              (item) =>
                item.event_id === eventId &&
                (item.status === "accepted" || item.status === "duplicate"),
            ),
        )
      ) {
        throw new Error(
          "Receiver did not acknowledge the retried event identities",
        );
      }
      const receipts = readdirSync(runDir)
        .filter((name) => /^fault\.receipt\.[0-9a-f]{32}\.json$/.test(name))
        .map(
          (name) =>
            JSON.parse(readFileSync(path.join(runDir, name), "utf8")) as {
              rule_id?: string;
              injected?: boolean;
              event_ids?: string[];
            },
        );
      if (
        !receipts.some(
          (receipt) =>
            receipt.rule_id === ruleId &&
            receipt.injected === true &&
            retriedIds.some((eventId) => receipt.event_ids?.includes(eventId)),
        )
      ) {
        throw new Error("Fault receipt does not identify the retried event");
      }
      writeFileSync(
        path.join(
          runDir,
          `web-telemetry-recovery-${randomBytes(8).toString("hex")}.json`,
        ),
        JSON.stringify(
          {
            result: "same_event_recovered",
            run_id: runId,
            fault_rule_id: ruleId,
            user_id: userId,
            failed_status: 503,
            recovered_status: 200,
            retried_event_ids: retriedIds,
            event_identity_checked_by_proof: true,
            owner_and_loki_checked_by_host_proof: false,
          },
          null,
          2,
        ),
      );
    } finally {
      // A consumed rule is inactive. An unconsumed rule must be disarmed;
      // cleanup failure must fail closed rather than affect later tests.
      if (
        existsSync(path.join(runDir, "fault.pending.json")) ||
        existsSync(path.join(runDir, "fault.active.json"))
      ) {
        execFileSync(
          python,
          [
            "-m",
            "dev.local_api_fault_proxy",
            "disarm",
            "--run-id",
            runId,
            "--rule-id",
            ruleId,
          ],
          { cwd: root, stdio: "ignore" },
        );
      }
    }
  } finally {
    if (switchState === "false") {
      const cleanup = await page.context().newPage();
      try {
        await cleanup.goto("/admin/login");
        const cleanupId = (value: string) => cleanup.getByTestId(value);
        if (await cleanupId("admin.auth.login.page").isVisible()) {
          await fillPrivate("admin.auth.login.email", adminEmail, cleanup);
          await fillPrivate(
            "admin.auth.login.password",
            adminPassword,
            cleanup,
          );
          await cleanupId("admin.auth.login.submit").click();
        }
        await expect(cleanupId("admin.auth.policy.page")).toBeVisible();
        const toggle = cleanupId("admin.auth.policy.registration_toggle");
        const switchElement = toggle.locator('[role="switch"]');
        const state = await ((await switchElement.count())
          ? switchElement.getAttribute("aria-checked")
          : toggle.getAttribute("aria-checked"));
        if (state === "true") {
          await toggle.click();
          const saved = cleanup.waitForResponse(
            (response) =>
              new URL(response.url()).pathname ===
                "/api/v1/admin/auth-policy" &&
              response.request().method() === "PATCH",
          );
          await cleanupId("admin.auth.policy.save").click();
          expect((await saved).status()).toBe(200);
        } else if (state !== "false") {
          throw new Error(
            "Registration policy state unavailable during cleanup",
          );
        }
      } catch {
        throw new Error("Isolated registration policy could not be restored");
      } finally {
        await cleanup.close();
      }
    }
  }
});
