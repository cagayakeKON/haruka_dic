const {
  chromium,
  expect,
} = require('../../tools/e2e/node_modules/@playwright/test');
const {
  selectText,
  closeStudy,
  studyResult,
} = require('./selection-helpers.cjs');
const fs = require('node:fs');

(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const results = [],
    errors = [];
  fs.mkdirSync('artifacts/design18', { recursive: true });
  try {
    for (const [platform, width, touch] of [
      ['phone', 320, true],
      ['phone', 390, true],
      ['desktop', 390, false],
      ['desktop', 1440, false],
    ]) {
      const page = await browser.newPage({
        viewport: { width, height: 844 },
        hasTouch: touch,
      });
      page.on('pageerror', (e) => errors.push(e.message));
      const route = async (value) => {
        await page.evaluate((value) => {
          location.hash = value;
        }, value);
        await page.waitForTimeout(120);
      };
      const action = (name) => page.locator(`[data-selection-action=${name}]`);
      const bubble = (word) =>
        page
          .locator('.word-bubble')
          .filter({ hasText: new RegExp(`^${word}$`) });
      const player = page.locator('.selection-player');
      const sentence = '窓を開けると、夏の風がそっと頬に触れた。';
      const openSentence = async () => {
        if (touch)
          await selectText(page, '[data-reading-sentence]', 'そっと', true);
        else await selectText(page, '[data-reading-sentence]', sentence);
        await expect(page.locator('.selection-preview')).toHaveText(sentence);
      };
      await page.goto(`http://127.0.0.1:8767/${platform}.html#novel`);
      await openSentence();
      await expect(page.locator('.selection-scope')).toHaveText('查询整句');
      await expect(bubble('そっと')).toHaveAttribute('aria-pressed', 'false');
      await bubble('風').click();
      await bubble('夏').click(); // Reverse click order still follows the sentence.
      await expect(page.locator('.selection-scope')).toHaveText('夏 / 風');
      await bubble('の').click();
      await expect(page.locator('.selection-scope')).toHaveText('夏の風');
      await bubble('の').click();
      await page.screenshot({
        path: `artifacts/design18/${platform}-${width}-bubbles.png`,
      });
      await action('query').click();
      await expect(
        page.locator(':is([role=dialog],[data-reader-panel]) .learning-card'),
      ).toHaveCount(2);
      await expect(
        page
          .locator(':is([role=dialog],[data-reader-panel]) .learning-title')
          .first(),
      ).toHaveText('夏');
      await expect(
        page
          .locator(':is([role=dialog],[data-reader-panel]) .learning-title')
          .last(),
      ).toHaveText('風');
      await page
        .locator(':is([role=dialog],[data-reader-panel]) [data-x=saveCard]')
        .last()
        .click();
      await page.getByRole('button', { name: '确认收藏', exact: true }).click();
      await expect(
        page
          .locator(':is([role=dialog],[data-reader-panel]) [data-x=saveCard]')
          .last(),
      ).toBeDisabled();
      await expect(
        page
          .locator(':is([role=dialog],[data-reader-panel]) [data-x=saveCard]')
          .first(),
      ).toBeEnabled();
      await closeStudy(page);
      await openSentence();
      await page.locator('.selection-adjust summary').click();
      await page
        .getByLabel('选区起点')
        .selectOption(String(sentence.indexOf('そっと')));
      await page
        .getByLabel('选区终点')
        .selectOption(String(sentence.indexOf('そっと') + 3));
      await expect(page.locator('.selection-scope')).toHaveText('そっと');
      await action('query').click();
      await expect(
        page.locator(':is([role=dialog],[data-reader-panel]) .learning-title'),
      ).toHaveText('そっと');
      await closeStudy(page);
      // Default query remains the full sentence, not a forced select-all gesture.
      await openSentence();
      await action('query').click();
      await expect(
        page.locator(':is([role=dialog],[data-reader-panel]) .learning-title'),
      ).toHaveText(sentence);
      await closeStudy(page);

      // Long-press context chooses the current sentence for a fresh queue.
      await action('continuous').click();
      await expect(player).toHaveAttribute('data-sentence', '1');
      await expect(page.locator('.is-speaking')).toHaveText(sentence);
      await page.waitForTimeout(450);
      await openSentence();
      const pausedAt = Number(await player.getAttribute('data-elapsed'));
      const ready = await player.getAttribute('data-prepared');
      await page.waitForTimeout(500);
      expect(Number(await player.getAttribute('data-elapsed'))).toBe(pausedAt);
      await expect(player).toHaveAttribute('data-prepared', ready);
      await bubble('そっと').click();
      await action('query').click();
      if (platform === 'phone') await expect(player).toHaveCount(0);
      else await expect(player).toContainText('已暂停'); // The non-modal reader keeps its paused controls.
      await page
        .locator(':is([role=dialog],[data-reader-panel]) [data-pronounce]')
        .click();
      await expect(player).toHaveAttribute('data-mode', 'single');
      await action('stop').click();
      await closeStudy(page);
      await expect(player).toHaveAttribute('data-mode', 'continuous');
      await expect(player).toContainText('已暂停');
      expect(Number(await player.getAttribute('data-elapsed'))).toBe(pausedAt);
      await page.screenshot({
        path: `artifacts/design18/${platform}-${width}-paused.png`,
      });
      await action('pause').click();
      await expect(player).toContainText('播放中');
      await expect
        .poll(async () => Number(await player.getAttribute('data-elapsed')))
        .toBeGreaterThan(pausedAt);
      await page.getByLabel('朗读语速').selectOption('1.5');
      await expect(player).toHaveAttribute('data-sentence', '2', {
        timeout: 8000,
      });
      await expect(page.locator('.is-speaking')).toHaveText(
        '机の上には、一通の手紙が置かれていた。',
      );
      await action('pause').click();
      const nextReady = await player.getAttribute('data-prepared');
      await page.waitForTimeout(500);
      await expect(player).toHaveAttribute('data-prepared', nextReady);
      await action('stop').click();
      await expect(page.locator('.is-speaking')).toHaveCount(0);
      // Single-sentence playback and the continuous queue reuse the same prepared mock item.
      await openSentence();
      await action('read').click();
      await expect(player).toHaveAttribute('data-prepared', nextReady);
      await action('stop').click();

      await route('notebooks');
      const row = page
        .locator('.collection-row')
        .filter({ hasText: 'そっと' })
        .first();
      await row.locator('[data-pronounce]').click();
      await expect(page.locator('[role=dialog]')).toHaveCount(0);
      await expect(player).toContainText('そっと');
      await action('stop').click();
      await row.locator('.collection-row-open').click();
      await page
        .locator(':is([role=dialog],[data-reader-panel]) [data-pronounce]')
        .click();
      await expect(player).toContainText('そっと');
      await action('stop').click();
      await closeStudy(page);
      await page.screenshot({
        path: `artifacts/design18/${platform}-${width}-words.png`,
      });
      await route('textbook');
      await page
        .locator('[data-action=textbookItem],[data-modal=textbookItem]')
        .nth(1)
        .click();
      await page
        .locator(':is([role=dialog],[data-reader-panel]) [data-pronounce]')
        .first()
        .click();
      await expect(player).toBeVisible();
      await closeStudy(page);
      await expect(player).toHaveCount(0);
      await route('examPrep');
      await expect(
        page.locator(
          '[data-study-text],[data-pronounce],[data-selection-action=continuous]',
        ),
      ).toHaveCount(0);
      expect(
        await page.evaluate(
          () => document.documentElement.scrollWidth <= innerWidth + 1,
        ),
      ).toBe(true);
      results.push(
        `${platform}/${width}: chips, ordered multi-target query, per-card collection, boundary adjustment, whole sentence, continuous pause/query/short speech/resume, highlight advance, bounded mock preparation, reuse, word/list/detail/textbook speakers, exam gate`,
      );
      await page.close();
    }
    expect(errors).toEqual([]);
    fs.writeFileSync(
      'artifacts/design18/results.json',
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
