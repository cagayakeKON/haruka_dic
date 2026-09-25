const {
  chromium,
  expect,
} = require("../../tools/e2e/node_modules/@playwright/test");
const fs = require("node:fs");

(async () => {
  const browser = await chromium.launch({ channel: "msedge", headless: true });
  const results = [];
  try {
    await Promise.all(
      ["desktop", "phone"].map(async (platform) => {
        const page = await browser.newPage({
          viewport: { width: platform === "desktop" ? 1440 : 390, height: 900 },
        });
        page.setDefaultTimeout(10000);
        const errors = [];
        page.on("pageerror", (error) => errors.push(error.message));
        await page.goto(`http://127.0.0.1:8767/${platform}.html#notebooks`);
        await page.locator("[data-x=switch]").click();
        await page.locator("[data-x=chooseBook][data-id=dailywords]").click();
        await expect(page.locator(".collection-row")).toHaveCount(3);
        await page.locator("[data-x=practice]").click();
        await expect(page).toHaveURL(/#exerciseBuilder/);
        await page.locator("[data-action=builderNext]").click();
        await expect(page.locator("main")).toContainText(/2 项内容/);
        await page.evaluate(() => {
          location.hash = "query";
        });
        await page
          .locator("[data-x=prompt]")
          .filter({ hasText: "翻译：" })
          .click();
        await expect(page.locator("#query-input")).toHaveValue(
          "翻译：夏の風がそっと頬に触れた。",
        );
        await page.locator("#query-input").press("Control+Enter");
        await expect(page.locator(".answer-card .collection-kind")).toHaveText(
          "句子 · 示例",
        );
        await page.locator("[data-x=saveCard]").click();
        await page
          .locator("[data-x-form=saveCard] [name=books]")
          .first()
          .check();
        await page
          .locator("[data-x-form=saveCard] button[type=submit]")
          .click();
        await expect(page.locator("[data-x=saveCard]")).toBeDisabled();
        await page.locator("[data-go=notebooks]").click();
        await page.locator("[data-x=kind][data-id=sentence]").click();
        await expect(page.locator(".collection-row")).toHaveCount(1);
        await page.locator("[data-x=entry]").click();
        await expect(page.getByRole("dialog")).toContainText(
          "「頬」读作「ほお」",
        );
        await page.keyboard.press("Escape");
        for (const width of [320, 390, 768, 1440]) {
          await page.setViewportSize({ width, height: 900 });
          expect(
            await page.evaluate(
              () => document.documentElement.scrollWidth > innerWidth + 1,
            ),
            `${platform} notebook ${width}`,
          ).toBe(false);
        }
        await page.setViewportSize({
          width: platform === "desktop" ? 1440 : 390,
          height: 900,
        });
        await page.locator("[data-x=kind][data-id=all]").click();
        await page.screenshot({
          path: `artifacts/design6/${platform}-notebooks-final.png`,
          fullPage: true,
        });
        await page.evaluate(() => {
          location.hash = "query";
        });
        await page.screenshot({
          path: `artifacts/design6/${platform}-query-final.png`,
          fullPage: true,
        });

        const imports = [];
        for (const type of ["novel", "textbook", "exam"]) {
          await page.evaluate(() => {
            location.hash = "library";
          });
          await page.locator("[data-go=import]").click();
          await page.locator(`[data-import-type=${type}]`).click();
          await page
            .locator(
              platform === "phone"
                ? "[data-go=import]"
                : "[data-action=importNext]",
            )
            .click();
          await page.locator("[data-file=material]").setInputFiles({
            name: `${type}.md`,
            mimeType: "text/markdown",
            buffer: Buffer.from("fictional example"),
          });
          await page.locator("[data-action=importNext]").click();
          await page.locator("[data-action=importConfirm]").click();
          await expect(page.getByRole("dialog")).toHaveAccessibleName(
            "任务进度",
          );
          const item = page
            .getByRole("dialog")
            .locator(".task-item")
            .filter({ hasText: `${type}.md` });
          const id = await item
            .locator("[data-job-open]")
            .getAttribute("data-job-open");
          imports.push({ type, id });
          await page.keyboard.press("Escape");
        }
        console.log(
          `${platform}: query type, source counts, layouts, import started`,
        );
        await page.locator("[data-x=tasks]").click();
        await expect(
          page
            .getByRole("dialog")
            .locator(`[data-job-open="${imports[2].id}"]`),
        ).toBeEnabled({ timeout: 65000 });
        for (const { type, id } of imports) {
          if (!(await page.getByRole("dialog").count())) {
            if (platform === "phone")
              await page.evaluate(() => {
                location.hash = "library";
              });
            await page.locator("[data-x=tasks]").click();
          }
          await page
            .getByRole("dialog")
            .locator(`[data-job-open="${id}"]`)
            .click();
          await expect(page.getByRole("dialog")).toHaveCount(0);
          await expect(page.locator(".sample-reader")).toContainText(
            `${type}.md`,
          );
          await expect(page).toHaveURL(
            new RegExp(
              `#${{ novel: "sampleReader", textbook: "sampleTextbook", exam: "sampleExamPrep" }[type]}$`,
            ),
          );
          if (type === "exam")
            await expect(
              page.getByRole("button", { name: "开始考试", exact: true }),
            ).toBeDisabled();
        }
        // Same route, different material: switch from imported novel to the built-in rain sample.
        await page.evaluate(() => {
          location.hash = "library";
        });
        await page.locator(`[data-material="${imports[0].id}"]`).click();
        if (platform === "desktop") {
          await page.locator("[data-x=tasks]").click();
          await page
            .getByRole("dialog")
            .locator("[data-job-open=rain]")
            .click();
        } else {
          // Library details also open the second novel through a modal.
          await page.evaluate(() => {
            location.hash = "library";
          });
          await page.locator("[data-x=materialActions][data-id=rain]").click();
          await page
            .getByRole("button", { name: "查看详情", exact: true })
            .click();
          await page.getByRole("dialog").locator("[data-x=openJob]").click();
        }
        await expect(page.getByRole("dialog")).toHaveCount(0);
        await expect(page.locator(".sample-reader")).toContainText(
          "雨が上がった",
        );
        expect(errors).toEqual([]);
        results.push(
          `${platform}: 6 review regressions and 4 layout cases passed`,
        );
        console.log(results.at(-1));
        await page.close();
      }),
    );
    fs.writeFileSync(
      "artifacts/design6/regressions.json",
      JSON.stringify(results, null, 2),
    );
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
