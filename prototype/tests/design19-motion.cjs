const {
  chromium,
  expect,
} = require('../../tools/e2e/node_modules/@playwright/test');
const { selectText } = require('./selection-helpers.cjs');
const fs = require('node:fs');

async function observeMotion(page) {
  await page.evaluate(() => {
    window.motionRecords = [];
    new MutationObserver(() => {
      for (const animation of document.getAnimations()) {
        const el = animation.effect?.target;
        if (
          !el?.matches(
            '.sheet,.dialog,.text-selection-toolbar,.word-bubble,.prototype-motion-exit',
          )
        )
          continue;
        if (
          window.motionRecords.some((record) => record.animation === animation)
        )
          continue;
        window.motionRecords.push({
          animation,
          target: el.className.trim(),
          duration: animation.effect.getTiming().duration,
          delay: animation.effect.getTiming().delay,
          initialOpacity: getComputedStyle(el).opacity,
          frames: animation.effect.getKeyframes().map((frame) => ({
            opacity: frame.opacity,
            transform: frame.transform,
          })),
        });
      }
    }).observe(document.body, { subtree: true, childList: true });
  });
}
async function longPress(page, touch) {
  if (touch) return selectText(page, '[data-reading-sentence]', 'そっと', true);
  const target = page
    .locator('[data-reading-sentence]')
    .filter({ hasText: 'そっと' });
  await target.scrollIntoViewIfNeeded();
  const point = await target.evaluate((el) => {
    const range = document.createRange();
    range.setStart(el.firstChild, 0);
    range.setEnd(el.firstChild, 1);
    const rect = range.getBoundingClientRect();
    return { x: rect.x + 3, y: rect.y + rect.height / 2 };
  });
  await page.mouse.move(point.x, point.y);
  await page.mouse.down();
  await page.waitForTimeout(650);
  await page.mouse.up();
}
(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const results = [],
    errors = [];
  fs.mkdirSync('artifacts/design19', { recursive: true });
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
      page.on('pageerror', (error) => {
        errors.push(error.message);
        console.error(`${platform}/${width}: ${error.message}`);
      });
      await page.goto(`http://127.0.0.1:8767/${platform}.html#novel`);
      await observeMotion(page);
      const action = (name) => page.locator(`[data-selection-action=${name}]`);
      const records = () =>
        page.evaluate(() =>
          window.motionRecords.map(({ animation, ...record }) => record),
        );
      // Plain selection remains useful for copying and never creates a study popup or pauses audio.
      await action('continuous').click();
      await selectText(page, '[data-reading-sentence]', 'そっと', false, false);
      await expect(
        page.locator('.text-selection-toolbar,[role=dialog]'),
      ).toHaveCount(0);
      await expect(page.locator('.selection-player')).toContainText('播放中');
      await action('stop').click();
      await longPress(page, touch);
      await expect(page.locator('.selection-preview')).toHaveText(
        '窓を開けると、夏の風がそっと頬に触れた。',
      );
      expect(
        (await records()).some(
          (record) =>
            record.target === 'text-selection-toolbar' &&
            record.duration === 240,
        ),
      ).toBe(true);
      expect(
        (await records()).some((record) => record.target === 'word-bubble'),
      ).toBe(true);
      const delayedWords = (await records()).filter(
        (record) => record.target === 'word-bubble' && record.delay > 0,
      );
      expect(delayedWords.length).toBeGreaterThan(0);
      expect(
        delayedWords.every((record) => record.initialOpacity === '0'),
      ).toBe(true);
      // A single hold must not rebuild/restart its floating panel on pointerup/selectionchange.
      expect(
        (await records()).filter(
          (record) => record.target === 'text-selection-toolbar',
        ),
      ).toHaveLength(1);
      await page.screenshot({
        path: `artifacts/design19/${platform}-${width}-sentence.png`,
      });
      await page
        .locator('.word-bubble')
        .filter({ hasText: /^そっと$/ })
        .click();
      await action('query').click();
      await expect(
        page.getByRole('dialog', { name: '查询结果' }),
      ).toBeVisible();
      expect(
        (await records()).some(
          (record) =>
            record.target === (platform === 'phone' ? 'sheet' : 'dialog') &&
            record.duration === 240,
        ),
      ).toBe(true);
      await page.screenshot({
        path: `artifacts/design19/${platform}-${width}-query.png`,
        animations: 'disabled',
      });
      await page.locator('[data-x=saveCard]').click();
      await page.getByRole('button', { name: '关闭', exact: true }).click();
      await expect(
        page.getByRole('dialog', { name: '查询结果' }),
      ).toBeVisible();
      await page.getByRole('button', { name: '关闭', exact: true }).click();
      await expect(page.locator('[role=dialog]')).toHaveCount(0);
      await expect(page.locator('.prototype-motion-exit')).toHaveCount(0);
      expect(
        (await records()).some(
          (record) =>
            record.target === 'prototype-motion-exit' &&
            record.duration === 150,
        ),
      ).toBe(true);
      await page.locator('[data-modal=readerSettings]').click();
      await page.waitForTimeout(280);
      const before = (await records()).length;
      await page.locator('[data-setting=readingFont]').selectOption('sans');
      await page.waitForTimeout(80);
      expect((await records()).length).toBe(before); // Same dialog re-render is not a new entrance.
      await page.getByRole('button', { name: '关闭', exact: true }).click();
      await expect(page.locator('.prototype-motion-exit')).toHaveCount(0);
      // Explicit keyboard activation remains available; selecting alone still does nothing.
      await selectText(page, '[data-reading-sentence]', 'そっと', false, false);
      await expect(page.locator('.text-selection-toolbar')).toHaveCount(0);
      await page.keyboard.press('Alt+Enter');
      await expect(action('read')).toBeFocused();
      await page.keyboard.press('Escape');
      await expect(page.locator('.text-selection-toolbar')).toHaveCount(0);
      // OS reduced motion suppresses WAAPI too, including ghost exits.
      await page.emulateMedia({ reducedMotion: 'reduce' });
      await page.evaluate(() => {
        window.motionRecords = [];
      });
      await longPress(page, touch);
      await page
        .locator('.word-bubble')
        .filter({ hasText: /^そっと$/ })
        .click();
      await action('query').click();
      await page.getByRole('button', { name: '关闭', exact: true }).click();
      await expect(page.locator('[role=dialog]')).toHaveCount(0);
      expect(await records()).toEqual([]);
      // The application's own preference has the same effect without OS assistance.
      await page.emulateMedia({ reducedMotion: 'no-preference' });
      await page.evaluate(() => {
        location.hash = 'appearance';
      });
      await page.locator('[data-toggle=reduceMotion]').check();
      await page.evaluate(() => {
        location.hash = 'novel';
      });
      await expect(
        page.locator('[data-reading-sentence]').first(),
      ).toBeVisible();
      await longPress(page, touch);
      await action('query').click();
      await expect(
        page.getByRole('dialog', { name: '查询结果' }),
      ).toBeVisible();
      await page.getByRole('button', { name: '关闭', exact: true }).click();
      await expect(page.locator('[role=dialog]')).toHaveCount(0);
      expect(await records()).toEqual([]);
      expect(
        await page.evaluate(
          () => document.documentElement.scrollWidth <= innerWidth + 1,
        ),
      ).toBe(true);
      results.push(
        `${platform}/${width}: plain selection no popup/no pause; touch or mouse hold; single entrance and word motion; query/collection/close animation; no reanimation on same-dialog updates; keyboard activation; OS and application reduced motion`,
      );
      await page.close();
    }
    expect(errors).toEqual([]);
    fs.writeFileSync(
      'artifacts/design19/results.json',
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
