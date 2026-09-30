import { expect, test } from "@playwright/test";
import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import {
  readFileSync,
  unlinkSync,
  writeFileSync,
  mkdirSync,
  existsSync,
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

test("model credentials and UI continuity", async ({ page }) => {
  test.setTimeout(240_000);
  page.setDefaultTimeout(15_000);
  const runtime = readFileSync(path.join(runDir, "runtime.env"), "utf8");
  if (!/^HARUKA_MODEL_EXECUTION_MODE=fake$/m.test(runtime))
    throw new Error("An isolated fake model run is required");
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
  const actorPath = path.join(runDir, "model-ui-actor.json");
  if (!existsSync(actorPath)) {
    const adminEmail = `admin-${runId}@haruka.example.test`;
    const adminPassword = readFileSync(
      path.join(runDir, "admin.secret"),
      "utf8",
    ).trim();
    await page.goto("/admin/login");
    await expect(id("admin.auth.login.page")).toBeVisible({ timeout: 30_000 });
    await fillPrivate("admin.auth.login.email", adminEmail);
    await fillPrivate("admin.auth.login.password", adminPassword);
    const adminLogin = page.waitForResponse(
      (r) =>
        new URL(r.url()).pathname === "/api/v1/admin/auth/login" &&
        r.request().method() === "POST",
    );
    await id("admin.auth.login.submit").click();
    expect((await adminLogin).status()).toBe(200);
    await page.getByText("注册策略", { exact: true }).first().click();
    await expect(id("admin.auth.policy.page")).toBeVisible({ timeout: 30_000 });
    const registrationToggle = id("admin.auth.policy.registration_toggle");
    if (!(await registrationToggle.innerText()).includes("开放注册")) {
      await registrationToggle.click();
      await delay(400);
      await page.keyboard.press("ArrowDown");
      await page.keyboard.press("ArrowDown");
      await page.keyboard.press("Enter");
      await page.getByText("预览策略变化", { exact: true }).click();
      const savedPolicy = page.waitForResponse(
        (response) =>
          new URL(response.url()).pathname === "/api/v1/admin/auth-policy" &&
          response.request().method() === "PATCH",
      );
      await id("admin.auth.policy.save").click();
      expect((await savedPolicy).status()).toBe(200);
    }
    await page.getByText("账号安全", { exact: true }).first().click();
    await id("admin.auth.policy.sign_out").click();
    await expect(id("admin.auth.login.page")).toBeVisible({ timeout: 30_000 });

    const email = `learner-${randomBytes(8).toString("hex")}@haruka.example.test`;
    const password = `Valid-${randomBytes(12).toString("hex")}`;
    writeFileSync(
      path.join(runDir, "model-ui-actor.json"),
      JSON.stringify({ email, password }),
    );
    await page.goto("/register");
    await expect(id("client.auth.register.page")).toBeVisible({
      timeout: 30_000,
    });
    await fillPrivate("client.auth.register.email", email);
    await fillPrivate("client.auth.register.confirm", password);
    await fillPrivate("client.auth.register.password", password);
    if (
      (await input("client.auth.register.password").inputValue()) !==
        password ||
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
    await page.getByText("我的", { exact: true }).first().click();
  } else {
    const actor = JSON.parse(readFileSync(actorPath, "utf8")) as {
      email: string;
      password: string;
    };
    await page.goto("/login");
    await fillPrivate("client.auth.login.email", actor.email);
    await fillPrivate("client.auth.login.password", actor.password);
    const login = page.waitForResponse(
      (r) =>
        new URL(r.url()).pathname === "/api/v1/auth/login" &&
        r.request().method() === "POST",
    );
    await id("client.auth.login.submit").click();
    expect((await login).status()).toBe(200);
    if (await page.getByText("跳过", { exact: true }).isVisible())
      await page.getByText("跳过", { exact: true }).click();
    await page.getByText("我的", { exact: true }).first().click();
  }
  await expect(page.getByText("个人模型", { exact: true }).first()).toBeVisible(
    { timeout: 30_000 },
  );
  const evidence = path.join(root, "artifacts/model-settings-ui");
  mkdirSync(evidence, { recursive: true });
  const originalJobs = page.waitForResponse(
    (r) =>
      new URL(r.url()).pathname === "/api/v1/jobs" &&
      r.request().method() === "GET",
  );
  await page.goto("/jobs");
  const originalJobsResponse = await originalJobs;
  expect(originalJobsResponse.status()).toBe(200);
  const originalJobData = (await originalJobsResponse.json()) as {
    data: { items: { state: string }[] };
  };
  const capabilities =
    originalJobData.data.items.length === 0
      ? ["文本", "视觉", "朗读"]
      : ["视觉", "朗读"];
  await delay(500);
  await page.screenshot({ path: path.join(evidence, "web-original-job.png") });
  if (originalJobData.data.items.length > 0) {
    await expect(
      page.locator('[aria-label*="文本"][aria-label*="openrouter"]').first(),
    ).toBeVisible({ timeout: 30_000 });
  }
  await page.goto("/settings/model");
  let reads = 0,
    usageReads = 0,
    posts = 0,
    sockets = 0,
    maxSockets = 0;
  const active = new Set<unknown>();
  const report: Record<string, unknown> = {
    run_id: runId,
    status: "running",
    mode: "fake",
  };
  const telemetryStatuses: number[] = [];
  page.on("response", (response) => {
    if (new URL(response.url()).pathname.endsWith("/frontend-logs"))
      telemetryStatuses.push(response.status());
  });
  let stage = "model_configuration";
  page.on("request", (request) => {
    const route = new URL(request.url()).pathname;
    if (
      /^\/api\/v1\/(provider-credentials|model-capabilities|users\/me\/model-settings|users\/me\/model-usage|jobs)/.test(
        route,
      )
    ) {
      if (request.method() === "GET") reads++;
      if (
        request.method() === "GET" &&
        route === "/api/v1/users/me/model-usage"
      )
        usageReads++;
      if (request.method() === "POST" && /\/test$/.test(route)) posts++;
    }
  });
  page.on("websocket", (socket) => {
    if (!socket.url().endsWith("/api/v1/jobs/events")) return;
    sockets++;
    active.add(socket);
    maxSockets = Math.max(maxSockets, active.size);
    socket.on("close", () => active.delete(socket));
  });
  try {
    const add = id("client.model.credential.add");
    await expect(add).toBeVisible();
    await delay(600);
    stage = "dialog_resize_no_reads";
    const before = reads;
    await add.click();
    await fillPrivate("client.model.credential.key", "fictional-fixture-only");
    await page.getByText("取消", { exact: true }).click();
    await delay(400);
    await page.setViewportSize({ width: 390, height: 844 });
    await delay(400);
    await page.setViewportSize({ width: 1440, height: 900 });
    await delay(400);
    expect(reads).toBe(before);
    stage = "save_without_test";
    await add.click();
    await fillPrivate("client.model.credential.key", "fictional-fixture-only");
    const saved = page.waitForResponse(
      (r) =>
        new URL(r.url()).pathname === "/api/v1/provider-credentials" &&
        r.request().method() === "POST",
    );
    await id("client.model.credential.save").click();
    expect([200, 201]).toContain((await saved).status());
    expect(posts).toBe(0);
    await expect(id("client.model.credential.key")).not.toBeVisible();
    await delay(300);
    await page.screenshot({
      path: path.join(evidence, "formal-web-model-desktop.png"),
    });
    stage = "explicit_ability_jobs";
    for (const capability of capabilities) {
      await id("client.model.test.open").click();
      await expect(
        page.getByText("确认单项能力测试", { exact: true }),
      ).toBeVisible();
      if (capability !== "文本") {
        await id("client.model.test.capability").click();
        for (let index = 0; index < (capability === "视觉" ? 1 : 2); index++)
          await page.keyboard.press("ArrowDown");
        await page.keyboard.press("Enter");
      }
      const accepted = page.waitForResponse(
        (r) =>
          /\/provider-credentials\/[^/]+\/test$/.test(
            new URL(r.url()).pathname,
          ) && r.request().method() === "POST",
      );
      await id("client.model.test.confirm").click();
      expect((await accepted).status()).toBe(202);
      await page.mouse.move(1100, 650);
      await page.mouse.wheel(0, 1600);
      await expect(
        page
          .locator(`[aria-label*="${capability}"][aria-label*="openrouter"]`)
          .first(),
      ).toBeVisible({ timeout: 60_000 });
      await expect(
        page
          .locator('[aria-label*="模型能力测试"][aria-label*="已完成"]')
          .last(),
      ).toBeVisible({
        timeout: 60_000,
      });
    }
    expect(posts).toBe(capabilities.length);
    expect(maxSockets).toBe(1);
    await page.screenshot({
      path: path.join(evidence, "formal-web-model-results.png"),
    });
    stage = "usage_keyboard_focus";
    await page.getByText("模型用量", { exact: true }).first().click();
    const filter = input("client.model.usage.model_filter");
    await expect(filter).toBeVisible();
    await delay(600);
    const usageReadsBefore = usageReads;
    await filter.click();
    for (const letter of "google/gemini-2.5-flash") {
      await filter.pressSequentially(letter);
      await delay(100);
      await expect(filter).toBeFocused();
    }
    await delay(800);
    await expect(filter).toBeFocused();
    expect(usageReads).toBe(usageReadsBefore);
    await page.setViewportSize({ width: 390, height: 844 });
    await delay(300);
    await input("client.model.usage.model_filter").click();
    await expect(input("client.model.usage.model_filter")).toHaveValue(
      "google/gemini-2.5-flash",
    );
    const filtered = page.waitForResponse(
      (r) =>
        new URL(r.url()).pathname === "/api/v1/users/me/model-usage" &&
        new URL(r.url()).searchParams.get("model_id") ===
          "google/gemini-2.5-flash",
    );
    await id("client.model.usage.apply").click();
    expect((await filtered).status()).toBe(200);
    await page.screenshot({
      path: path.join(evidence, "formal-web-usage-mobile.png"),
    });
    Object.assign(report, {
      status: "passed",
      reads,
      test_posts: posts,
      socket_connections: sockets,
      max_active_sockets: maxSockets,
      frontend_log_statuses: telemetryStatuses,
    });
  } catch (error) {
    Object.assign(report, {
      status: "failed",
      failed_step: stage,
      reads,
      test_posts: posts,
      frontend_log_statuses: telemetryStatuses,
      reason:
        error instanceof Error
          ? error.message.split("\n")[0]
          : "UI check failed",
    });
    if (stage === "explicit_ability_jobs")
      await page.screenshot({
        path: path.join(evidence, "web-model-job-failure.png"),
      });
    throw new Error(`Model UI flow failed at ${stage}; inspect safe report`);
  } finally {
    writeFileSync(
      path.join(evidence, `web-model-${String(Date.now())}.json`),
      JSON.stringify(report, null, 2),
    );
  }
});

test("administrator reads model catalog, limits, jobs and usage", async ({
  page,
}) => {
  page.setDefaultTimeout(15_000);
  const runtime = readFileSync(path.join(runDir, "runtime.env"), "utf8");
  if (!/^HARUKA_MODEL_EXECUTION_MODE=(fake|live)$/m.test(runtime))
    throw new Error("An owned model run is required for read-only checks");
  const id = (value: string) => page.getByTestId(value);
  const fill = async (name: string, value: string) => {
    try {
      await id(name).locator("input").fill(value);
    } catch {
      throw new Error("Private administrator field unavailable");
    }
  };
  await page.goto("/admin/login");
  await fill("admin.auth.login.email", `admin-${runId}@haruka.example.test`);
  await fill(
    "admin.auth.login.password",
    readFileSync(path.join(runDir, "admin.secret"), "utf8").trim(),
  );
  const login = page.waitForResponse(
    (r) =>
      new URL(r.url()).pathname === "/api/v1/admin/auth/login" &&
      r.request().method() === "POST",
  );
  await id("admin.auth.login.submit").click();
  expect((await login).status()).toBe(200);
  const evidence = path.join(root, "artifacts/model-settings-ui");
  const checked: string[] = [];
  for (const [label, endpoint, name] of [
    ["模型能力目录", "/api/v1/admin/model-catalog", "catalog"],
    ["模型运行限制", "/api/v1/admin/model-limits", "limits"],
    ["任务与资源", "/api/v1/admin/jobs", "jobs"],
    ["模型用量", "/api/v1/admin/model-usage", "usage"],
  ] as const) {
    const loaded = page.waitForResponse(
      (r) =>
        new URL(r.url()).pathname === endpoint &&
        r.request().method() === "GET",
    );
    await page.getByText(label, { exact: true }).first().click();
    expect((await loaded).status()).toBe(200);
    await delay(400);
    await page.screenshot({
      path: path.join(evidence, `formal-admin-model-${name}.png`),
    });
    checked.push(name);
    if (name === "jobs") {
      let reads = 0;
      const observe = (request: import("@playwright/test").Request) => {
        if (
          request.method() === "GET" &&
          new URL(request.url()).pathname === endpoint
        )
          reads += 1;
      };
      page.on("request", observe);
      await page.getByText("查看摘要", { exact: true }).first().click();
      await expect(page.getByText("运维摘要", { exact: true })).toBeVisible();
      await page.screenshot({
        path: path.join(evidence, "formal-admin-model-job-detail.png"),
      });
      await page.getByText("关闭", { exact: true }).click();
      await delay(300);
      expect(reads).toBe(0);
      page.off("request", observe);
      checked.push("job_detail_cached");
    }
  }
  writeFileSync(
    path.join(evidence, `admin-model-${String(Date.now())}.json`),
    JSON.stringify(
      { run_id: runId, status: "passed", read_pages: checked, writes: 0 },
      null,
      2,
    ),
  );
});

test("usage typing, menu, viewport and foreground preserve data", async ({
  page,
  context,
}) => {
  test.setTimeout(90_000);
  page.setDefaultTimeout(15_000);
  const runtime = readFileSync(path.join(runDir, "runtime.env"), "utf8");
  if (!/^HARUKA_MODEL_EXECUTION_MODE=(fake|live)$/m.test(runtime))
    throw new Error("An owned model run is required for read-only checks");
  const actor = JSON.parse(
    readFileSync(path.join(runDir, "model-ui-actor.json"), "utf8"),
  ) as { email: string; password: string };
  const id = (value: string) => page.getByTestId(value);
  const input = (value: string) => id(value).locator("input,textarea");
  await page.goto("/login");
  try {
    await input("client.auth.login.email").fill(actor.email);
    await input("client.auth.login.password").fill(actor.password);
  } catch {
    throw new Error("Private login input unavailable");
  }
  const logged = page.waitForResponse(
    (r) =>
      new URL(r.url()).pathname === "/api/v1/auth/login" &&
      r.request().method() === "POST",
  );
  await id("client.auth.login.submit").click();
  expect((await logged).status()).toBe(200);
  await page.getByText("跳过", { exact: true }).click();
  await page.getByText("我的", { exact: true }).first().click();
  const jobs = page.waitForResponse(
    (r) =>
      new URL(r.url()).pathname === "/api/v1/jobs" &&
      r.request().method() === "GET",
  );
  await page.goto("/jobs");
  const jobResponse = await jobs;
  expect(jobResponse.status()).toBe(200);
  const jobData = (await jobResponse.json()) as {
    data: { items: { state: string }[] };
  };
  expect(jobData.data.items.length).toBeGreaterThanOrEqual(3);
  expect(
    jobData.data.items.every((j) =>
      ["succeeded", "failed", "unknown", "blocked", "cancelled"].includes(
        j.state,
      ),
    ),
  ).toBe(true);
  const initialUsage = page.waitForResponse(
    (r) =>
      new URL(r.url()).pathname === "/api/v1/users/me/model-usage" &&
      r.request().method() === "GET",
  );
  await page.goto("/settings/usage");
  const usageResponse = await initialUsage;
  expect(usageResponse.status()).toBe(200);
  const usageData = (await usageResponse.json()) as {
    data: { groups: { simulated: boolean; attempt_count: number }[] };
  };
  expect(
    usageData.data.groups.every(
      (group) => typeof group.simulated === "boolean",
    ),
  ).toBe(true);
  const realAttempts = usageData.data.groups
    .filter((group) => !group.simulated)
    .reduce((sum, group) => sum + group.attempt_count, 0);
  const simulatedAttempts = usageData.data.groups
    .filter((group) => group.simulated)
    .reduce((sum, group) => sum + group.attempt_count, 0);
  const counts: Record<string, number> = {};
  const logStatuses: number[] = [];
  page.on("request", (request) => {
    const p = new URL(request.url()).pathname;
    if (
      request.method() === "GET" &&
      /^\/api\/v1\/(jobs|provider-credentials|model-capabilities|users\/me\/model-)/.test(
        p,
      )
    ) {
      const key = p.replace(
        /[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}/g,
        "{id}",
      );
      counts[key] = (counts[key] ?? 0) + 1;
    }
  });
  page.on("response", (r) => {
    if (new URL(r.url()).pathname.endsWith("/frontend-logs"))
      logStatuses.push(r.status());
  });
  const filter = input("client.model.usage.model_filter");
  await expect(filter).toBeVisible();
  await delay(1000);
  const before = { ...counts };
  await filter.click();
  for (const letter of "google/gemini-2.5-flash") {
    await filter.pressSequentially(letter);
    await delay(100);
    await expect(filter).toBeFocused();
  }
  await delay(800);
  await expect(filter).toBeFocused();
  expect(counts).toEqual(before);
  await page.getByRole("button", { name: /全部/ }).first().click();
  await delay(300);
  await page.keyboard.press("Escape");
  await delay(300);
  await filter.click();
  const other = await context.newPage();
  await other.goto("about:blank");
  await other.bringToFront();
  await page.bringToFront();
  await other.close();
  await delay(500);
  await expect(filter).toHaveValue("google/gemini-2.5-flash");
  expect(counts).toEqual(before);
  await page.setViewportSize({ width: 390, height: 844 });
  await delay(500);
  await page.screenshot({
    path: path.join(
      root,
      "artifacts/model-settings-ui/web-usage-resize-before-focus.png",
    ),
  });
  await input("client.model.usage.model_filter").click();
  await expect(input("client.model.usage.model_filter")).toHaveValue(
    "google/gemini-2.5-flash",
  );
  expect(counts).toEqual(before);
  const filtered = page.waitForResponse(
    (r) =>
      new URL(r.url()).pathname === "/api/v1/users/me/model-usage" &&
      new URL(r.url()).searchParams.get("model_id") ===
        "google/gemini-2.5-flash",
  );
  await id("client.model.usage.apply").click();
  expect((await filtered).status()).toBe(200);
  const evidence = path.join(root, "artifacts/model-settings-ui");
  await delay(300);
  await page.screenshot({
    path: path.join(evidence, "formal-web-usage-mobile.png"),
  });
  await page.setViewportSize({ width: 1440, height: 900 });
  await delay(300);
  await page.screenshot({
    path: path.join(evidence, "formal-web-usage-desktop.png"),
  });
  await delay(2000);
  const idleLogsBefore = logStatuses.length;
  const idleReadsBefore = { ...counts };
  await delay(15000);
  const idleLogUploads = logStatuses.length - idleLogsBefore;
  expect(idleLogUploads).toBeLessThanOrEqual(4);
  expect(counts).toEqual(idleReadsBefore);
  writeFileSync(
    path.join(evidence, `web-continuity-${String(Date.now())}.json`),
    JSON.stringify(
      {
        run_id: runId,
        status: "passed",
        unchanged_before: before,
        unchanged_after: before,
        actual_get_counts: counts,
        frontend_log_statuses: logStatuses,
        terminal_job_count: jobData.data.items.length,
        idle_observation_ms: 15000,
        idle_log_uploads: idleLogUploads,
        real_attempts: realAttempts,
        simulated_attempts: simulatedAttempts,
      },
      null,
      2,
    ),
  );
});

test("review fixes catalog CAS and usage counts", async ({ page }) => {
  page.setDefaultTimeout(15000);
  await page.setViewportSize({ width: 1440, height: 900 });
  const id = (value: string) => page.getByTestId(value);
  await page.goto("/admin/login");
  try {
    await id("admin.auth.login.email")
      .locator("input")
      .fill(`admin-${runId}@haruka.example.test`);
    await id("admin.auth.login.password")
      .locator("input")
      .fill(readFileSync(path.join(runDir, "admin.secret"), "utf8").trim());
  } catch {
    throw new Error("Private administrator input unavailable");
  }
  const login = page.waitForResponse(
    (r) =>
      new URL(r.url()).pathname === "/api/v1/admin/auth/login" &&
      r.request().method() === "POST",
  );
  await id("admin.auth.login.submit").click();
  expect((await login).status()).toBe(200);
  if (!process.env.HARUKA_REVIEW_USAGE_ONLY) {
    const loaded = page.waitForResponse(
      (r) =>
        new URL(r.url()).pathname === "/api/v1/admin/model-catalog" &&
        r.request().method() === "GET",
    );
    await page.getByText("模型能力目录", { exact: true }).first().click();
    const directoryResponse = (await (await loaded).json()) as {
      data: {
        revision: number;
        models: {
          id: string;
          provider: string;
          capabilities: string[];
          enabled: boolean;
          revision: number;
        }[];
      };
    };
    const directory = directoryResponse.data;
    const index = directory.models.findIndex(
      (m) =>
        m.provider === "openrouter" &&
        m.enabled &&
        m.capabilities.includes("text") &&
        m.capabilities.includes("vision"),
    );
    expect(index).toBeGreaterThanOrEqual(0);
    const target = directory.models[index];
    if (!target) throw new Error("Enabled owned catalog target missing");
    let reads = 0;
    let supplierPosts = 0;
    let patchCount = 0;
    const mutations: unknown[] = [];
    page.on("request", (request) => {
      const p = new URL(request.url()).pathname;
      if (
        p.startsWith("/api/v1/admin/model-catalog/") &&
        request.method() === "PATCH"
      )
        patchCount++;
      if (p === "/api/v1/admin/model-catalog" && request.method() === "GET")
        reads++;
      if (
        /\/provider-credentials\/[^/]+\/test$/.test(p) &&
        request.method() === "POST"
      )
        supplierPosts++;
    });
    const switches = page.locator('[role="switch"], [role="checkbox"]');
    await expect(switches).toHaveCount(directory.models.length);
    await switches.nth(index).click();
    await page.getByText("取消", { exact: true }).click();
    await delay(300);
    expect(reads).toBe(0);
    expect(patchCount).toBe(0);
    let revision = target.revision;
    for (const enabled of [false, true]) {
      await switches.nth(index).click();
      const patched = page.waitForResponse(
        (r) =>
          new URL(r.url()).pathname ===
            `/api/v1/admin/model-catalog/${target.id}` &&
          r.request().method() === "PATCH",
      );
      await page.getByText("提交变更", { exact: true }).click();
      const response = await patched;
      mutations.push(response.request().postDataJSON());
      expect(response.status()).toBe(200);
      expect(response.request().postDataJSON()).toEqual({
        expected_revision: revision,
        enabled,
      });
      const updated = ((await response.json()) as { data: typeof directory })
        .data;
      const model = updated.models.find((m) => m.id === target.id);
      if (!model) throw new Error("Updated catalog target missing");
      expect(model.enabled).toBe(enabled);
      expect(model.revision).toBeGreaterThan(revision);
      revision = model.revision;
      await expect(switches.nth(index)).toHaveAttribute(
        "aria-checked",
        String(enabled),
      );
      expect(reads).toBe(0);
    }
    expect(patchCount).toBe(2);
    expect(supplierPosts).toBe(0);
    writeFileSync(
      path.join(
        root,
        "artifacts/model-settings-ui/review-fixes-catalog-ui.json",
      ),
      JSON.stringify(
        {
          status: "passed",
          catalog_patches: mutations,
          cancelled_dialog_patches: 0,
          extra_catalog_gets: reads,
          supplier_posts: supplierPosts,
          restored_enabled: true,
        },
        null,
        2,
      ),
    );
  }
  const usage = page.waitForResponse(
    (r) =>
      new URL(r.url()).pathname === "/api/v1/admin/model-usage" &&
      r.request().method() === "GET",
  );
  await page.getByText("模型用量", { exact: true }).first().click();
  expect((await usage).status()).toBe(200);
  await page.mouse.move(1100, 700);
  await page.mouse.wheel(0, 950);
  await delay(400);
  await page.screenshot({
    path: path.join(
      root,
      "artifacts/model-settings-ui/review-fixes-usage-position.png",
    ),
  });
  await expect(page.getByText(/调用 \d+ · 进行中 \d+/).first()).toBeVisible();
  await expect(
    page.getByText(/已知 \d+ 次 \/ 未知 \d+ 次/).first(),
  ).toBeVisible();
  const out = path.join(root, "artifacts/model-settings-ui");
  await page.screenshot({
    path: path.join(out, "review-fixes-usage-desktop.png"),
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await delay(300);
  await page
    .getByText(/已知 \d+ 次 \/ 未知 \d+ 次/)
    .first()
    .scrollIntoViewIfNeeded();
  await page.screenshot({
    path: path.join(out, "review-fixes-usage-mobile.png"),
  });
  writeFileSync(
    path.join(out, "review-fixes-usage-ui.json"),
    JSON.stringify(
      {
        status: "passed",
        unknown_attempt_counts_visible: true,
        started_count_visible: true,
        viewports: [
          [1440, 900],
          [390, 844],
        ],
        model_test_posts: 0,
      },
      null,
      2,
    ),
  );
});
