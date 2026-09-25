const {
  chromium,
  expect,
} = require('../../tools/e2e/node_modules/@playwright/test');
const { selectText } = require('./selection-helpers.cjs');
const fs = require('node:fs');
(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const results = [],
    errors = [];
  try {
    for (const platform of ['phone', 'desktop']) {
      const page = await browser.newPage({
        viewport: { width: platform === 'phone' ? 320 : 1440, height: 844 },
        hasTouch: true,
      });
      page.on('pageerror', (error) => errors.push(error.message));
      await page.goto(`http://127.0.0.1:8767/${platform}.html#novel`);
      const action = (name) => page.locator(`[data-selection-action=${name}]`);
      const player = page.locator('.selection-player');
      await selectText(page, '[data-reading-sentence]', 'そっと', true);
      const bubbles = page.locator('.word-bubble');
      for (const index of [0, 2, 4, 6]) await bubbles.nth(index).click();
      await expect(action('query')).toBeDisabled();
      await expect(page.locator('.selection-scope')).toContainText(
        '最多查询3组',
      );
      await bubbles.nth(6).click();
      await expect(action('query')).toBeEnabled();
      await page.locator('.selection-adjust summary').click();
      await page.getByLabel('选区起点').selectOption('3');
      await page.getByLabel('选区终点').selectOption('1');
      await expect(action('query')).toBeDisabled();
      await expect(page.locator('.selection-scope')).toHaveText(
        '终点需要在起点之后',
      );
      await page.keyboard.press('Escape');
      const last = await page
        .locator('[data-reading-sentence]')
        .last()
        .innerText();
      await selectText(page, '[data-reading-sentence]', last, true);
      await page.keyboard.press('Escape');
      await action('continuous').click();
      await expect(player).toHaveAttribute('data-sentence', '4');
      await expect(player).toHaveAttribute('data-prepared', '1');
      await page.getByLabel('朗读语速').selectOption('1.5');
      await expect(player).toContainText('本章已读完', { timeout: 8000 });
      await action('pause').click();
      await expect(player).toHaveAttribute('data-sentence', '4');
      await expect(player).toHaveAttribute('data-prepared', '1');
      await expect(player).toContainText('播放中');
      await action('stop').click();
      // Scroll during playback disables automatic follow until the user resumes.
      await selectText(page, '[data-reading-sentence]', '朝の光', true);
      await page.keyboard.press('Escape');
      await action('continuous').click();
      await page.getByLabel('朗读语速').selectOption('1.5');
      await page.mouse.wheel(0, 250);
      await page.waitForTimeout(250);
      const scroll = await page.evaluate(() => scrollY);
      await expect(player).toHaveAttribute('data-sentence', '1', {
        timeout: 8000,
      });
      expect(await page.evaluate(() => scrollY)).toBe(scroll);
      await action('stop').click();
      await page.evaluate(() => {
        location.hash = 'library';
      });
      await expect(page.locator('[data-material="rain"]')).toContainText(
        '可阅读',
        { timeout: 65000 },
      );
      await page.locator('[data-material="rain"]').first().click();
      await expect(page.locator('[data-reading-sentence]')).toHaveCount(3);
      await action('continuous').click();
      await expect(player).toContainText('雨が上がった。');
      await page.locator('[data-go=library]').last().click();
      await expect(player).toHaveCount(0);
      results.push(
        `${platform}: multi-range cap, invalid boundary, last-sentence completion/replay stays in scope, manual scroll preserved, second novel queue and navigation cleanup`,
      );
      await page.close();
    }
    expect(errors).toEqual([]);
    fs.writeFileSync(
      'artifacts/design18/boundaries.json',
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
