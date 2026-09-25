const {
  chromium,
  expect,
} = require("../../tools/e2e/node_modules/@playwright/test");
const {
  selectText,
  closeStudy,
  studyResult,
} = require("./selection-helpers.cjs");
const fs = require("node:fs");

(async () => {
  const browser = await chromium.launch({ channel: "msedge", headless: true });
  const results = [],
    errors = [];
  fs.mkdirSync("artifacts/design16", { recursive: true });
  try {
    for (const [platform, width, touch] of [
      ["phone", 320, true],
      ["phone", 390, true],
      ["desktop", 390, false],
      ["desktop", 1440, false],
    ]) {
      const page = await browser.newPage({
        viewport: { width, height: 844 },
        hasTouch: touch,
      });
      page.on("pageerror", (error) => errors.push(error.message));
      const url = `http://127.0.0.1:8767/${platform}.html`;
      const route = async (value) => {
        await page.evaluate((value) => {
          location.hash = value;
        }, value);
        await page.waitForTimeout(150);
      };
      const action = (name) => page.locator(`[data-selection-action=${name}]`);
      await page.goto(`${url}#novel`);
      await expect(
        page.locator(
          "[data-term],[data-action=toggleSpeech],[data-action=collectTerm]",
        ),
      ).toHaveCount(0);
      const prose = ".prose p,.reading-prose p";
      // Touch defaults to the full sentence; drag can refine to a word on either layout.
      if (touch) {
        await selectText(page, prose, "そっと", true);
        await expect(page.locator(".selection-preview")).toHaveText(
          "窓を開けると、夏の風がそっと頬に触れた。",
        );
        await action("read").click();
        await expect(page.locator(".selection-player")).toContainText(
          "夏の風がそっと頬に触れた。",
        );
        await action("stop").click();
      }
      await selectText(page, prose, "そっと");
      await expect(page.locator(".selection-preview")).toHaveText("そっと");
      await page.screenshot({
        path: `artifacts/design16/${platform}-${width}-selection.png`,
        fullPage: true,
      });
      await action("query").click();
      await expect(
        page.locator(":is([role=dialog],[data-reader-panel]) .learning-card"),
      ).toContainText("轻轻地；悄悄地");
      await page.locator("[data-x=saveCard]").click();
      await page.locator("[name=books]").first().check();
      await page.getByRole("button", { name: "确认收藏", exact: true }).click();
      await expect(
        page.locator(
          ":is([role=dialog],[data-reader-panel]) [data-x=saveCard]",
        ),
      ).toBeDisabled();
      await page.screenshot({
        path: `artifacts/design16/${platform}-${width}-saved.png`,
        fullPage: true,
      });
      await selectText(
        page,
        ":is([role=dialog],[data-reader-panel]) .learning-explanation",
        "用于动作轻柔，或不希望打扰别人的场景。",
        touch,
      );
      await action("read").click();
      await expect(page.locator(".selection-player")).toContainText(
        "无实际音频",
      );
      await expect(page.locator(".selection-player")).toContainText(
        "用于动作轻柔",
      );
      await action("pause").click();
      await expect(action("pause")).toHaveText("继续");
      await page.getByLabel("朗读语速").selectOption({ label: "1.2×" });
      await page.screenshot({
        path: `artifacts/design16/${platform}-${width}-player.png`,
        fullPage: true,
      });
      await action("stop").click();
      // A nested query uses the actual selected phrase and retains its result source.
      await selectText(
        page,
        ":is([role=dialog],[data-reader-panel]) .learning-title",
        "そっと",
        touch,
      );
      await action("query").click();
      await expect(page.locator(".selection-query-origin")).toContainText(
        "查询结果",
      );
      await closeStudy(page);
      await expect(
        page.locator(":is([role=dialog],[data-reader-panel]) .learning-card"),
      ).toBeVisible();
      await closeStudy(page);
      await route("notebooks");
      await expect(
        page.locator(".collection-row").filter({ hasText: "そっと" }),
      ).not.toHaveCount(0);
      await selectText(page, ".collection-word-line", "そっと", touch);
      await expect(page.locator("[role=dialog]")).toHaveCount(0);
      await action("query").click();
      await expect(
        page.locator(":is([role=dialog],[data-reader-panel]) .learning-card"),
      ).toBeVisible();
      await closeStudy(page);
      await route("practice");
      await selectText(
        page,
        ".answer-copy",
        await page.locator(".answer-copy").first().innerText(),
        touch,
      );
      await expect(
        page.locator("[data-practice-answer][aria-pressed=true]"),
      ).toHaveCount(0);
      await expect(action("read")).toBeVisible();
      await page.keyboard.press("Escape");
      await page.locator("[data-practice-answer]").first().click();
      await page.locator("[data-action=practiceSubmit]").click();
      await selectText(
        page,
        ".feedback p",
        (await page.locator(".feedback p").innerText()).slice(0, 5),
      );
      await expect(action("read")).toBeVisible();
      await page.keyboard.press("Escape");
      await route("report");
      await selectText(page, ".panel p", "Unit 02");
      await action("query").click();
      await expect(page.locator("[role=dialog]")).toContainText(
        "没有内置查询示例",
      );
      await expect(
        page.locator(
          ":is([role=dialog],[data-reader-panel]) [data-x=saveCard]",
        ),
      ).toHaveCount(0);
      await closeStudy(page);
      await route("textbook");
      await page
        .locator("[data-action=textbookItem],[data-modal=textbookItem]")
        .first()
        .click();
      await selectText(
        page,
        "[role=dialog] p[lang=ja]",
        (await page.locator("[role=dialog] p[lang=ja]").innerText()).slice(
          0,
          4,
        ),
      );
      await expect(action("read")).toBeVisible();
      await page.keyboard.press("Escape");
      await page.keyboard.press("Escape");
      await route("examPrep");
      await expect(
        page.locator(
          "[data-study-text],.text-selection-toolbar,.selection-player",
        ),
      ).toHaveCount(0);
      await page
        .locator("[data-action=examScript],[data-modal=examScript]")
        .first()
        .click();
      await expect(page.locator("[data-study-text]")).toHaveCount(0);
      await page.keyboard.press("Escape");
      await route("query");
      await expect(
        page.locator(".selection-player,.text-selection-toolbar"),
      ).toHaveCount(0);
      await page.locator("#query-input").fill("そっと");
      await page.locator("#query-input").press("Control+Enter");
      await expect(page.locator(".learning-card").last()).toContainText(
        "轻轻地",
      );
      await selectText(page, ".learning-title", "そっと");
      // The explicit Alt+Enter action in selectText focuses the sentence control.
      await expect(action("read")).toBeFocused();
      await page.keyboard.press("Enter");
      await expect(page.locator(".selection-player")).toBeVisible();
      await route("settings");
      await expect(
        page.locator(
          ".selection-player,.text-selection-toolbar,[data-study-text]",
        ),
      ).toHaveCount(0);
      expect(
        await page.evaluate(
          () => document.documentElement.scrollWidth <= innerWidth + 1,
        ),
      ).toBe(true);
      results.push(
        `${platform}/${width}: ${touch ? "touch sentence and mouse range" : "mouse range"}, query, collection, nested query, Chinese playback, row/answer safety, textbook, unknown result, exam exclusion, keyboard, navigation cleanup`,
      );
      await page.close();
    }
    expect(errors).toEqual([]);
    fs.writeFileSync(
      "artifacts/design16/results.json",
      JSON.stringify({ results, errors }, null, 2),
    );
    console.log(JSON.stringify({ results, errors }, null, 2));
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
