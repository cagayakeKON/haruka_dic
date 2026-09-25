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
async function longPress(page, text, touch) {
  if (touch) return selectText(page, '[data-reading-sentence]', text, true);
  const target = page
    .locator('[data-reading-sentence]')
    .filter({ hasText: text })
    .first();
  await target.scrollIntoViewIfNeeded();
  const point = await target.evaluate((el, text) => {
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
      if (node.parentElement.closest('rt,rp')) continue;
      const offset = node.textContent.indexOf(text);
      if (offset < 0) continue;
      const range = document.createRange();
      range.setStart(node, offset);
      range.setEnd(node, offset + 1);
      const rect = range.getBoundingClientRect();
      return { x: rect.x + rect.width / 2, y: rect.y + rect.height / 2 };
    }
    throw new Error(`Text not found: ${text}`);
  }, text);
  await page.mouse.move(point.x, point.y);
  await page.mouse.down();
  await page.waitForTimeout(650);
  await page.mouse.up();
}
(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const results = [],
    errors = [];
  fs.mkdirSync('artifacts/design20', { recursive: true });
  try {
    for (const [platform, width, touch] of [
      ['phone', 320, true],
      ['phone', 390, true],
      ['desktop', 390, false],
      ['desktop', 1440, false],
    ]) {
      console.log(`Checking ${platform}/${width}`);
      const page = await browser.newPage({
        viewport: { width, height: 844 },
        hasTouch: touch,
      });
      page.on('pageerror', (error) => {
        errors.push(error.message);
        console.error(error.message);
      });
      const action = (name) => page.locator(`[data-novel="${name}"]`);
      const checkbox = (kind) => page.locator(`[data-novel-cache="${kind}"]`);
      const progress = (kind) =>
        page.locator(`.novel-progress[data-kind="${kind}"]`);
      const close = async () => {
        await closeStudy(page);
        await expect(page.locator('[role=dialog]')).toHaveCount(0);
      };
      const complete = () =>
        expect(action('start')).toHaveText('所选内容已就绪', {
          timeout: 12000,
        });
      await page.goto(`http://127.0.0.1:8767/${platform}.html#novel`);
      await expect(page.locator('[data-reading-sentence]')).toHaveCount(5);
      await expect(page.locator('ruby')).toHaveCount(0);
      await action('prepare').first().click();
      await expect(checkbox('analysis')).toBeChecked();
      await expect(checkbox('audio')).toBeChecked();
      await checkbox('analysis').uncheck();
      await checkbox('audio').uncheck();
      await expect(action('start')).toBeDisabled();
      await expect(
        page.locator('[data-novel-preparation-state]'),
      ).toContainText('至少选择');
      await checkbox('analysis').check();
      await action('start').click();
      await expect(
        progress('analysis').locator('progress'),
      ).not.toHaveAttribute('value', '0');
      await page.locator('[data-novel-chapter]').selectOption('3');
      await checkbox('analysis').uncheck();
      await page.locator('[data-novel-chapter]').selectOption('2');
      await expect(checkbox('analysis')).toBeChecked();
      await expect(checkbox('audio')).not.toBeChecked();
      await expect(checkbox('analysis')).toBeDisabled();
      await action('pause').click();
      const paused = await progress('analysis').getAttribute('data-generated');
      await page.waitForTimeout(950);
      await expect(progress('analysis')).toHaveAttribute(
        'data-generated',
        paused,
      );
      await expect(progress('audio')).toHaveAttribute('data-generated', '0');
      await action('start').click();
      await page.locator('.novel-demo summary').click();
      await action('fail').click();
      await expect(
        page.locator('[data-novel-preparation-state]'),
      ).toContainText('已中断');
      await action('start').click();
      await complete();
      await expect(progress('analysis')).toHaveAttribute('data-generated', '5');
      await expect(progress('audio')).toHaveAttribute('data-generated', '0');
      await page.screenshot({
        path: `artifacts/design20/${platform}-${width}-analysis-only.png`,
        animations: 'disabled',
      });
      await close();
      await page.locator('[data-mode=analysis]').click();
      await expect(page.locator('ruby').first()).toBeVisible();
      const canonical = await page
        .locator('[data-reading-sentence]')
        .nth(1)
        .getAttribute('data-canonical-text');
      await page.screenshot({
        path: `artifacts/design20/${platform}-${width}-ruby.png`,
        animations: 'disabled',
      });
      // Analysis sentence keyboard targets must still allow ordinary mouse copying.
      await selectText(page, '[data-reading-sentence]', 'そっと', false, false);
      expect(await page.evaluate(() => getSelection().toString())).toBe(
        'そっと',
      );
      await expect(
        page.locator('.text-selection-toolbar,[role=dialog]'),
      ).toHaveCount(0);
      // Real long press must win over sentence click; readings never enter query text.
      await longPress(page, 'そっと', touch);
      await expect(page.locator('.selection-preview')).toHaveText(canonical);
      await expect(page.locator('[role=dialog]')).toHaveCount(0);
      await expect(
        page.locator('[data-reader-panel] .learning-card'),
      ).toHaveCount(0);
      await page.locator('[data-selection-action=dismiss]').click();
      await page.locator('[data-reading-sentence]').nth(1).click();
      await expect(studyResult(page, '句子解析')).toBeVisible();
      await expect(page.locator('.learning-title')).toHaveText(canonical);
      await expect(action('prepareAudio')).toBeVisible();
      await action('next').click();
      await expect(page.locator('.learning-title')).toHaveText(
        '机の上には、一通の手紙が置かれていた。',
      );
      await page.locator('[data-x=saveCard]').click();
      await page.getByRole('button', { name: '确认收藏', exact: true }).click();
      await expect(studyResult(page, '句子解析')).toBeVisible();
      await expect(page.locator('[data-x=saveCard]')).toBeDisabled();
      await close();
      await expect(page.locator('[data-novel-sentence]').nth(2)).toBeFocused();
      await longPress(page, '机', touch);
      await expect(page.locator('.selection-preview')).toHaveText(
        '机の上には、一通の手紙が置かれていた。',
      );
      await page.locator('[data-selection-action=query]').click();
      await expect(page.locator('[data-x=saveCard]')).toBeDisabled();
      await close();
      await action('prepare').first().click();
      await checkbox('analysis').uncheck();
      await checkbox('audio').check();
      await action('start').click();
      await complete();
      await expect(progress('analysis')).toHaveAttribute('data-generated', '5');
      await expect(progress('audio')).toHaveAttribute('data-generated', '5');
      await close();
      await page.locator('[data-reading-sentence]').nth(1).click();
      await page.getByRole('button', { name: '朗读原句', exact: true }).click();
      await expect(page.locator('.playback-text')).toHaveText(canonical);
      await expect(page.locator('.selection-player')).toHaveAttribute(
        'data-prepared',
        '5',
      );
      await page.locator('[data-selection-action=pause]').click();
      await expect(page.locator('.selection-player')).toContainText('已暂停');
      await page.screenshot({
        path: `artifacts/design20/${platform}-${width}-sentence.png`,
        animations: 'disabled',
      });
      await close();
      await page.locator('[data-selection-action=continuous]').click();
      await expect(page.locator('.selection-player')).toHaveAttribute(
        'data-prepared',
        '5',
      );
      await expect(page.locator('.playback-text')).not.toContainText('まど');
      await page.locator('[data-selection-action=stop]').click();
      // Another chapter, audio only. No background expansion to AI or another chapter.
      await action('prepare').first().click();
      await page.locator('[data-novel-chapter]').selectOption('0');
      await checkbox('analysis').uncheck();
      await expect(checkbox('audio')).toBeChecked();
      await action('start').click();
      await complete();
      await expect(progress('analysis')).toHaveAttribute('data-generated', '0');
      await expect(progress('audio')).toHaveAttribute('data-generated', '2');
      await page.locator('[data-novel-chapter]').selectOption('1');
      await checkbox('analysis').check();
      await action('start').click();
      await complete();
      await expect(progress('analysis')).toHaveAttribute('data-generated', '2');
      await expect(progress('audio')).toHaveAttribute('data-generated', '2');
      await page.screenshot({
        path: `artifacts/design20/${platform}-${width}-both.png`,
        animations: 'disabled',
      });
      await close();
      await page.locator('[data-modal=chapters]').click();
      await page
        .getByRole('dialog')
        .locator('[data-novel="chapter"]')
        .filter({ hasText: '海边的邮筒' })
        .click();
      await expect(page.locator('[data-reading-sentence]')).toHaveCount(2);
      await page.locator('[data-reading-sentence]').first().click();
      await expect(studyResult(page, '句子解析')).toContainText('尚未准备');
      await expect(page.locator('[data-x=saveCard]')).toHaveCount(0);
      await expect(
        page.getByRole('button', { name: '朗读原句', exact: true }),
      ).toBeVisible();
      await close();
      expect(
        await page.evaluate(
          () => document.documentElement.scrollWidth <= innerWidth + 1,
        ),
      ).toBe(true);
      // Scope reset follows real prototype logout navigation.
      await page.evaluate(() => {
        location.hash = 'login';
      });
      await expect(page.locator('[data-novel-sentence]')).toHaveCount(0);
      results.push(
        `${platform}/${width}: multi-select empty/analysis/audio/both; pause/failure/retry only missing; separate chapter state; ruby canonical selection and playback; sentence navigation, collection, cached audio reuse; missing analysis gate`,
      );
      await page.close();
    }
    expect(errors).toEqual([]);
    fs.writeFileSync(
      'artifacts/design20/results.json',
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
