const {
  chromium,
  expect,
} = require('../../tools/e2e/node_modules/@playwright/test');
const fs = require('node:fs');

(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const results = [];
  const errors = [];
  fs.mkdirSync('artifacts/design12', { recursive: true });
  const fits = async (page) => {
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth + 1,
      ),
    ).toBe(true);
  };
  try {
    for (const [platform, width] of [
      ['phone', 320],
      ['phone', 390],
      ['desktop', 390],
      ['desktop', 1440],
    ]) {
      const page = await browser.newPage({ viewport: { width, height: 844 } });
      page.setDefaultTimeout(8000);
      page.on('pageerror', (error) => errors.push(error.message));
      const label = `${platform}-${width}`;
      const url = `http://127.0.0.1:8767/${platform}.html`;
      await page.goto(`${url}#exerciseBuilder`);
      await expect(page.locator('[data-action=builderNext]')).toBeEnabled();
      await page.locator('[data-source=collection]').check();
      await expect(
        page.locator('#source-collection [data-practice-collection]'),
      ).toHaveCount(5);
      await expect(page.locator('.exercise-selection-count')).toContainText(
        '2 项内容',
      );
      await page.locator('[data-practice-collection=smile]').check();
      await expect(page.locator('.exercise-selection-count')).toContainText(
        '3 项内容',
      );
      await fits(page);
      await page.evaluate(() => window.scrollTo(0, 0));
      await page.screenshot({
        path: `artifacts/design12/${label}-sources.png`,
        fullPage: true,
      });
      await page.locator('[data-action=builderNext]').click();
      await expect(page.locator('.exercise-preview-list li')).toHaveCount(3);
      await expect(page.locator('.exercise-preview-list')).toContainText(
        '微笑む',
      );
      await expect(page.locator('.exercise-preview-list')).toContainText(
        '单词本 / 手选收藏',
      );
      await expect(page.locator('[data-action=generateDemo]')).toBeDisabled();
      await page.locator('[data-practice-repeat]').check();
      await expect(page.locator('[data-action=generateDemo]')).toBeEnabled();
      await page.locator('[data-practice-type]').selectOption('词义选择');
      await expect(page.locator('[data-practice-repeat]')).not.toBeChecked();
      await expect(page.locator('[data-action=generateDemo]')).toBeDisabled();
      await page.locator('[data-practice-count]').selectOption('1 题');
      await expect(page.locator('[data-action=generateDemo]')).toBeEnabled();
      await expect(page.locator('.exercise-repeat')).toHaveCount(0);
      await expect(page.locator('.exercise-review')).toContainText(
        '词义选择 · 1 题',
      );
      await fits(page);
      await page.evaluate(() => window.scrollTo(0, 0));
      await page.screenshot({
        path: `artifacts/design12/${label}-review.png`,
        fullPage: true,
      });
      await page.locator('[data-action=builderBack]').click();
      await expect(
        page.locator('[data-practice-collection=smile]'),
      ).toBeChecked();
      if (platform === 'phone') await page.goForward();
      else await page.goBack();
      await expect(page.locator('[data-practice-count]')).toHaveValue('1 题');
      if (platform === 'phone') await page.goBack();
      else await page.goForward();
      await expect(
        page.locator('[data-practice-collection=smile]'),
      ).toBeChecked();
      await page.locator('[data-practice-collection=smile]').uncheck();
      await page.locator('[data-action=builderNext]').click();
      await expect(page.locator('.exercise-preview-list li')).toHaveCount(2);
      await page.locator('[data-action=generateDemo]').click();
      await expect(page).toHaveURL(/#practice/);
      await expect(page.getByRole('dialog')).toHaveCount(0);
      results.push(
        `${label}: inline source choice, actual deduplicated preview, shortage guard, fresh consent, history and one confirmation`,
      );

      await page.goto(`${url}#exerciseBuilder?step=2`);
      await page.reload();
      await page.locator('[data-action=builderBack]').click();
      await expect(page.locator('[data-source=notebook]')).toBeVisible();
      await page.locator('[data-source=textbook]').check();
      await expect(
        page.locator('#source-textbook [data-practice-unit]'),
      ).toBeVisible();
      await page.locator('[data-setting=activeLanguage]').selectOption('英语');
      await expect(page.locator('[data-source=textbook]')).toBeDisabled();
      await expect(page.locator('[data-source=textbook]')).not.toBeChecked();
      await expect(page.locator('[data-practice-unit]')).toHaveCount(0);
      await page.locator('[data-action=builderNext]').click();
      await expect(page.locator('.exercise-preview-list li')).toHaveCount(1);
      await expect(page.locator('.exercise-preview-list')).toContainText(
        'glimmer',
      );
      await expect(page.locator('.exercise-preview-list')).not.toContainText(
        'そっと',
      );
      await page.locator('[data-action=builderBack]').click();
      await page.locator('[data-source=notebook]').uncheck();
      await expect(page.locator('[data-action=builderNext]')).toBeDisabled();
      await fits(page);
      results.push(
        `${label}: direct step-two return, unavailable language sources and empty-selection guard`,
      );

      await page.goto(`${url}#query`);
      const composer = await page.locator('.query-composer').boundingBox();
      const prompts = await page.locator('.query-prompts').boundingBox();
      expect(composer.y + composer.height).toBeLessThan(prompts.y);
      const send = await page
        .getByRole('button', { name: '发送问题' })
        .boundingBox();
      expect(send.y + send.height).toBeLessThan(760);
      await fits(page);
      await page.evaluate(() => window.scrollTo(0, 0));
      await page.screenshot({
        path: `artifacts/design12/${label}-query.png`,
        fullPage: true,
      });
      await page.locator('#query-input').fill('保留我的问题');
      await page
        .getByRole('button', { name: 'に 和 へ 有什么区别？', exact: true })
        .click();
      await expect(page.locator('#query-input')).toHaveValue(
        '保留我的问题\nに 和 へ 有什么区别？',
      );
      await expect(page.locator('#query-input')).toBeFocused();
      await page.locator('#query-input').fill('甲'.repeat(1999));
      await page
        .getByRole('button', { name: 'そっと 是什么意思？', exact: true })
        .click();
      await expect(page.locator('#query-input')).toHaveValue('甲'.repeat(1999));
      await expect(page.locator('#query-input')).toBeFocused();
      await page.locator('#query-input').fill('');
      await expect(page.locator('[data-query-error]')).toBeHidden();
      await page
        .getByRole('button', { name: 'に 和 へ 有什么区别？', exact: true })
        .click();
      await page.getByRole('button', { name: '发送问题' }).click();
      await expect(page.locator('.answer-card .collection-kind')).toHaveText(
        '语法 · 示例',
      );
      await expect(page.locator('.query-welcome')).toHaveCount(0);
      await expect(page.locator('#query-input')).toHaveValue('');
      await expect(page.locator('[data-x=saveCard]')).toBeEnabled();
      await fits(page);
      results.push(
        `${label}: input-first above-fold layout, safe example insertion, limit guard and answer card`,
      );
      await page.close();
    }
    expect(errors).toEqual([]);
    fs.writeFileSync(
      'artifacts/design12/task-flows.json',
      JSON.stringify(results, null, 2),
    );
    console.log(
      `PASS: ${results.length} focused task-flow groups; no JS errors.`,
    );
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
