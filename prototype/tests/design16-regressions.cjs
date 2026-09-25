const {
  chromium,
  expect,
} = require("../../tools/e2e/node_modules/@playwright/test");
const { selectText } = require("./selection-helpers.cjs");
const fs = require("node:fs");
(async () => {
  const browser = await chromium.launch({ channel: "msedge", headless: true });
  const results = [],
    errors = [];
  try {
    for (const platform of ["phone", "desktop"]) {
      const page = await browser.newPage({
        viewport: { width: platform === "phone" ? 390 : 1440, height: 844 },
      });
      page.on("pageerror", (error) => errors.push(error.message));
      await page.goto(`http://127.0.0.1:8767/${platform}.html#practice`);
      const route = async (name) => {
        await page.evaluate((name) => {
          location.hash = name;
        }, name);
        await page.waitForTimeout(100);
      };
      // Drag ends in the containing button's blank area, not in a selectable span.
      const answer = page.locator("[data-practice-answer]").first();
      const point = await answer.locator(".answer-copy").boundingBox();
      const button = await answer.boundingBox();
      await page.mouse.move(point.x + 1, point.y + point.height / 2);
      await page.mouse.down();
      await page.mouse.move(
        button.x + button.width - 8,
        point.y + point.height / 2,
        { steps: 12 },
      );
      await page.mouse.up();
      await expect(answer).toHaveAttribute("aria-pressed", "false");
      await page.keyboard.press("Escape");
      await route("notebooks");
      const row = page.locator(".collection-row-open").first();
      const start = await row.locator("strong").boundingBox(),
        end = await row.locator(".collection-meaning").boundingBox();
      await page.mouse.move(start.x + 1, start.y + start.height / 2);
      await page.mouse.down();
      await page.mouse.move(end.x + end.width - 1, end.y + end.height / 2, {
        steps: 12,
      });
      await page.mouse.up();
      await expect(page.locator("[role=dialog]")).toHaveCount(0);
      await page.keyboard.press("Escape");
      await row.click();
      await expect(
        page.getByRole("dialog", { name: "收藏详情" }),
      ).toBeVisible();
      await selectText(page, ".learning-title", "そっと");
      await page.locator("[data-selection-action=query]").click();
      await page.locator("[data-x=saveCard]").click();
      await page.getByRole("button", { name: "关闭", exact: true }).click();
      await expect(
        page.getByRole("dialog", { name: "查询结果" }),
      ).toBeVisible();
      await expect(page.locator("[data-x=saveCard]")).toBeEnabled();
      if (platform === "phone") await page.goBack();
      else
        await page.getByRole("button", { name: "关闭", exact: true }).click();
      await expect(
        page.getByRole("dialog", { name: "收藏详情" }),
      ).toBeVisible();
      await expect(page.locator("[data-study-text]")).toBeFocused();
      await page.getByRole("button", { name: "关闭", exact: true }).click();
      await route("textbook");
      await page
        .locator("[data-action=textbookItem],[data-modal=textbookItem]")
        .first()
        .click();
      const text = await page.locator("[role=dialog] p[lang=ja]").innerText();
      await selectText(page, "[role=dialog] p[lang=ja]", text.slice(0, 4));
      await page.locator("[data-selection-action=query]").click();
      await expect(
        page.getByRole("dialog", { name: "查询结果" }),
      ).toBeVisible();
      await page.getByRole("button", { name: "关闭", exact: true }).click();
      await expect(page.locator("[role=dialog] p[lang=ja]")).toHaveText(text);
      await expect(page.locator("[role=dialog] p[lang=ja]")).toBeFocused();
      await page.getByRole("button", { name: "关闭", exact: true }).click();
      await route("mistakes");
      const mistakeTitle = await page
        .locator("[data-study-text]")
        .first()
        .innerText();
      await selectText(page, "[data-study-text]", mistakeTitle.slice(0, 4));
      await expect(page.locator("[data-selection-action=read]")).toBeVisible();
      await page.keyboard.press("Escape");
      await page.locator("[data-mistake]").first().click();
      await selectText(page, "[data-study-text]", mistakeTitle.slice(0, 4));
      await expect(page.locator("[data-selection-action=query]")).toBeVisible();
      await page.keyboard.press("Escape");
      const answerText = await page
        .locator(".surface p[data-study-text],.panel p[data-study-text]")
        .first()
        .innerText();
      await selectText(
        page,
        ".surface p[data-study-text],.panel p[data-study-text]",
        answerText.slice(0, 4),
      );
      await page.locator("[data-selection-action=read]").click();
      await expect(page.locator(".selection-player")).toBeVisible();
      await route("security");
      await page.locator("[data-action=logout]").click();
      await expect(
        page.locator(
          ".text-selection-toolbar,.selection-player,[data-study-text]",
        ),
      ).toHaveCount(0);
      await expect(page.locator("body")).not.toContainText("轻轻地；悄悄地");
      results.push(
        `${platform}: drag-to-padding and cross-child selection do not activate controls; cancel collection and nested modal return restore source/focus; logout clears selection UI`,
      );
      await page.close();
    }
    expect(errors).toEqual([]);
    fs.writeFileSync(
      "artifacts/design16/regressions.json",
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
