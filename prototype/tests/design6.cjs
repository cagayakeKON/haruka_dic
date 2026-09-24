/* Scoped browser regression for DESIGN6. Start prototype/serve.py first. */
const {
  chromium,
  expect,
} = require("../../tools/e2e/node_modules/@playwright/test");
const fs = require("node:fs");
const path = require("node:path");
const output = path.resolve("artifacts/design6");
fs.mkdirSync(output, { recursive: true });

(async () => {
  const browser = await chromium.launch({ channel: "msedge", headless: true });
  const errors = [];
  const checks = [];
  try {
    for (const platform of ["desktop", "phone"]) {
      const page = await browser.newPage({
        viewport: { width: platform === "desktop" ? 1440 : 390, height: 900 },
      });
      page.on("pageerror", (error) =>
        errors.push(`${platform}: ${error.message}`),
      );
      // Fault injection closes an actual socket; reconnect still uses the real demo server.
      await page.addInitScript(() => {
        const Native = window.WebSocket;
        window.__demoSockets = [];
        window.WebSocket = class extends Native {
          constructor(...args) {
            super(...args);
            window.__demoSockets.push(this);
          }
        };
      });
      const frames = [];
      page.on("websocket", (ws) =>
        ws.on("framereceived", (frame) =>
          frames.push(JSON.parse(String(frame.payload))),
        ),
      );
      await page.goto(`http://127.0.0.1:8767/${platform}.html#library`);
      await expect(
        page.locator("[data-progress=rain] progress"),
      ).not.toHaveAttribute("value", "0", { timeout: 10000 });
      await page.evaluate(() => window.__demoSockets[0].close());
      await expect(page.locator("[data-progress=rain]")).toContainText(
        "连接中断",
      );
      await expect
        .poll(() => page.evaluate(() => window.__demoSockets.length))
        .toBe(2);
      await expect(page.locator("[data-progress=rain]")).toContainText(
        "解析中 ·",
      );
      checks.push(`${platform}: actual WebSocket frames and reconnect`);
      if (platform === "desktop") {
        await expect(page.locator("[data-go=notifications]")).toHaveCount(1);
        await expect(page.locator("[data-x=tasks]")).toHaveCount(1);
        await page.locator("[data-x=tasks]").click();
        await expect(page.locator(".task-drawer")).toBeVisible();
        await page.getByRole("button", { name: "关闭", exact: true }).click();
      }
      await page.locator("[data-x=materialDetails][data-id=summer]").click();
      await expect(page.getByRole("dialog")).toContainText("夏の手紙");
      await expect(page).toHaveURL(/#library$/);
      await page.keyboard.press("Escape");
      await page.locator("[data-material=summer]").click();
      await expect(page).toHaveURL(/#novel$/);
      await page.goBack();
      await page.locator("[data-material=daily]").click();
      await expect(page).toHaveURL(/#textbook$/);
      await page.goBack();
      await page.locator("[data-material=n2]").click();
      await expect(page).toHaveURL(/#examPrep$/);
      await page.goBack();
      checks.push(`${platform}: material direct routes and metadata dialog`);

      await page.locator("[data-go=notebooks]").click();
      await expect(page.locator(".collection-row")).toHaveCount(6);
      await page.locator("[data-x=entry][data-id=grammar-direction]").click();
      await expect(page.getByRole("dialog")).toContainText("目的地与移动方向");
      await expect(page).toHaveURL(/#notebooks$/);
      await page.keyboard.press("Escape");
      await expect(
        page.locator("[data-x=entry][data-id=grammar-direction]"),
      ).toBeFocused();
      await page.locator("[data-x=switch]").click();
      await page.locator("[data-x=manageBook][data-id=dailywords]").click();
      await page.locator("[name=title]").fill("日常收藏");
      await page.locator("[data-x-form=rename] button[type=submit]").click();
      await expect(page.getByRole("dialog")).toContainText("日常收藏");
      await page.locator("[data-x=chooseBook][data-id=dailywords]").click();
      await expect(page.getByRole("dialog")).toHaveCount(0);
      await expect(page.locator(".collection-row")).toHaveCount(3);
      await page.locator("[data-x=switch]").click();
      await page.locator("[data-x=manageBook][data-id=dailywords]").click();
      await page.locator("[data-x=deleteBook]").click();
      await expect(page.getByRole("dialog")).toHaveAccessibleName(
        "删除单词本？",
      );
      await page.locator("[data-x=confirmDeleteBook]").click();
      await page.keyboard.press("Escape");
      await expect(page.locator(".collection-row")).toHaveCount(6);
      checks.push(
        `${platform}: mixed list, dialogs, focus, rename/delete preserves entries`,
      );

      await page.locator("[data-x=add]").click();
      await page.locator("[name=kind]").selectOption("word");
      await page.locator("[name=word]").fill("朝");
      await page.locator("[name=meaning]").fill("早晨");
      await page.locator("[data-x-form=entry] button[type=submit]").click();
      await page.keyboard.press("Escape");
      await page.locator("[data-go=dailyWords]").click();
      await expect(page.locator(".collection-row")).toHaveCount(3);
      await expect(page.locator(".collection-list")).toContainText("朝");
      await page.locator("[data-x-date]").fill("2000-01-01");
      await expect(page.locator(".empty")).toContainText("这天没有加入单词");
      await page.goBack();
      checks.push(`${platform}: daily additions and empty date`);

      await page.locator("[data-go=query]").click();
      await page
        .locator("[data-x=prompt]")
        .filter({ hasText: "に 和 へ" })
        .click();
      await expect(page.locator("#query-input")).toHaveValue(
        "に 和 へ 有什么区别？",
      );
      await page.locator("#query-input").press("Control+Enter");
      await expect(page.locator(".answer-card")).toHaveCount(1);
      await page.locator("[data-x=saveCard]").click();
      await expect(page.getByRole("dialog")).not.toContainText(
        "English sparks",
      );
      await page.locator("[data-x-form=saveCard] button[type=submit]").click();
      await expect(page.locator("[data-x=saveCard]")).toBeDisabled();
      await page.locator("#query-input").fill("天空为什么是蓝色的？");
      await page.getByRole("button", { name: "发送问题" }).click();
      await page.locator("[data-x=saveCard]").last().click();
      await page.locator("[data-x-form=saveCard] button[type=submit]").click();
      await page.locator("[data-go=notebooks]").click();
      await page.locator("[data-x=kind][data-id=answer]").click();
      await expect(page.locator(".collection-row")).toHaveCount(1);
      await page.locator("[data-x=entry]").click();
      await expect(page.getByRole("dialog")).toContainText("蓝光比红光更容易");
      await page.keyboard.press("Escape");
      await page.locator("[data-x=kind][data-id=all]").click();
      checks.push(
        `${platform}: query prompts, keyboard send, language-safe full-card favorite`,
      );

      for (const width of platform === "desktop"
        ? [320, 390, 768, 1024, 1440, 1920]
        : [320, 390, 430]) {
        await page.setViewportSize({ width, height: 900 });
        for (const route of ["notebooks", "dailyWords", "query", "library"]) {
          await page.evaluate((route) => {
            location.hash = route;
          }, route);
          await expect(
            page.locator(".collection-page,.query-page"),
          ).toBeVisible();
          const overflow = await page.evaluate(
            () => document.documentElement.scrollWidth > innerWidth + 1,
          );
          expect(
            overflow,
            `${platform}/${route}/${width} horizontal overflow`,
          ).toBe(false);
        }
      }
      checks.push(`${platform}: affected route width matrix`);
      await page.setViewportSize({
        width: platform === "desktop" ? 1440 : 390,
        height: 900,
      });
      await page.evaluate(() => {
        location.hash = "library";
      });
      await expect(page.locator("[data-progress=rain]")).toContainText(
        "可阅读",
        { timeout: 65000 },
      );
      expect(frames.some((f) => f.status === "completed")).toBe(true);
      await page.locator("[data-material=rain]").click();
      await expect(page.locator(".sample-reader")).toContainText(
        "雨が上がった",
      );
      await page.evaluate(() => {
        location.hash = "notebooks";
      });
      await page.screenshot({
        path: path.join(output, `${platform}-notebooks.png`),
        fullPage: true,
      });
      await page.evaluate(() => {
        location.hash = "query";
      });
      await page.screenshot({
        path: path.join(output, `${platform}-query.png`),
        fullPage: true,
      });
      checks.push(`${platform}: server completion and reader`);
      await page.close();
      console.log(
        `${platform}: ${checks.filter((x) => x.startsWith(platform)).length} groups passed`,
      );
    }
    expect(errors).toEqual([]);
    fs.writeFileSync(
      path.join(output, "checks.json"),
      JSON.stringify({ checks, layoutCases: 36, errors }, null, 2),
    );
    console.log(
      `PASS: ${checks.length} groups; 36 layout cases; no page errors`,
    );
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
