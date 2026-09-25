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
  fs.mkdirSync('artifacts/design22', { recursive: true });
  try {
    for (const [platform, width] of [
      ['phone', 320],
      ['phone', 390],
      ['desktop', 1440],
      ['desktop', 3840],
    ]) {
      console.log(`Checking ${platform}/${width}`);
      const page = await browser.newPage({
        viewport: { width, height: width === 3840 ? 2160 : 900 },
      });
      page.on('pageerror', (error) => errors.push(error.message));
      const route = async (value) => {
        await page.evaluate((value) => {
          location.hash = value;
        }, value);
        await page.waitForTimeout(180);
      };
      await page.goto(
        `http://127.0.0.1:8767/${platform}.html?v=design22#queryPreferences`,
      );
      const budget = page.locator('[name=contextBudget]');
      await expect(budget).toHaveValue('10000');
      await budget.fill('999');
      await page
        .getByRole('button', { name: '保存查询偏好', exact: true })
        .click();
      expect(await budget.evaluate((el) => el.validity.valid)).toBe(false);
      await page.locator('[data-context-preset="20000"]').click();
      await page
        .getByRole('button', { name: '保存查询偏好', exact: true })
        .click();
      await expect(page.locator('[data-learning-status]')).toContainText(
        '下一次查询',
      );
      await page.screenshot({
        path: `artifacts/design22/${platform}-${width}-context.png`,
        fullPage: true,
      });
      await route('query');
      const send = async (context) => {
        const box = page.locator('[name=explicitContext]');
        if (!(await box.isVisible()))
          await page.locator('.query-context-input summary').click();
        await box.fill(context);
        await page.locator('#query-input').fill('そっと 是什么意思？');
        await page
          .getByRole('button', { name: '发送问题', exact: true })
          .click();
      };
      await send('夏の風がそっと頬に触れた。');
      const first = await page
        .locator('.learning-card')
        .last()
        .getAttribute('data-card-id');
      await expect(page.locator('.query-context-detail').last()).toContainText(
        '解释已保存',
      );
      await send('夏の風がそっと頬に触れた。');
      expect(
        await page
          .locator('.learning-card')
          .last()
          .getAttribute('data-card-id'),
      ).toBe(first);
      await expect(page.locator('.query-context-detail').last()).toContainText(
        '已复用本机解释',
      );
      await send('赤ちゃんを起こさないよう、そっと歩いた。');
      expect(
        await page
          .locator('.learning-card')
          .last()
          .getAttribute('data-card-id'),
      ).not.toBe(first);
      const cardCount = await page.locator('.learning-card').count();
      const png = await page.evaluate(() => {
        const canvas = document.createElement('canvas');
        canvas.width = canvas.height = 20;
        return canvas.toDataURL('image/png').split(',')[1];
      });
      await page.locator('[data-query-file=album]').setInputFiles({
        name: 'context.png',
        mimeType: 'image/png',
        buffer: Buffer.from(png, 'base64'),
      });
      await expect(page.locator('[data-x-form=query]')).toHaveAttribute(
        'aria-busy',
        'false',
      );
      await send('夏の風がそっと頬に触れた。');
      await expect(page.locator('.learning-card')).toHaveCount(cardCount);
      await expect(
        page.getByRole('status').filter({ hasText: '图片尚未识别' }),
      ).toContainText('图片尚未识别');
      await page.locator('[data-pronounce]').last().click();
      await expect(page.locator('.selection-player')).toBeVisible();
      await page.locator('[data-selection-action=stop]').click();
      await route('cache');
      await expect(page.locator('[data-saved-query-count]')).toHaveText('2');
      await expect(page.locator('[data-saved-audio-count]')).toHaveText('1');
      await page.locator('[data-modal=clearCache]').click();
      await page.locator('[data-action=clearCacheConfirm]').click();
      await expect(page.locator('[data-local-query-count]')).toHaveText('0');
      await expect(page.locator('[data-local-audio-count]')).toHaveText('0');
      await expect(page.locator('[data-saved-query-count]')).toHaveText('2');
      await expect(page.locator('.prototype-motion-exit')).toHaveCount(0);
      await page.screenshot({
        path: `artifacts/design22/${platform}-${width}-cache.png`,
        fullPage: true,
      });
      await route('query');
      await send('夏の風がそっと頬に触れた。');
      expect(
        await page
          .locator('.learning-card')
          .last()
          .getAttribute('data-card-id'),
      ).toBe(first);
      await expect(page.locator('.query-context-detail').last()).toContainText(
        '已取回保存的解释',
      );
      await route('queryPreferences');
      await expect(budget).toHaveValue('20000');
      await budget.fill('10000');
      await page
        .getByRole('button', { name: '保存查询偏好', exact: true })
        .click();
      await route('query');
      await send('夏の風がそっと頬に触れた。');
      expect(
        await page
          .locator('.learning-card')
          .last()
          .getAttribute('data-card-id'),
      ).toBe(first);
      await route('speech');
      await page
        .locator('[data-learning-setting=model]')
        .selectOption('routerSpeech');
      await expect(page.locator('[data-learning-setting=voice]')).toHaveValue(
        '日语 · 柔和',
      );
      await page.locator('[data-learning-setting=format]').selectOption('wav');
      await expect(page.locator('[data-learning-setting=format]')).toHaveValue(
        'wav',
      );
      await expect(page.locator('[data-learning-setting=style]')).toHaveCount(
        0,
      );
      await page
        .locator('[data-learning-setting=model]')
        .selectOption('routerAudio');
      await expect(page.locator('[data-learning-setting=voice]')).toHaveValue(
        '日语 · 明亮',
      );
      await expect(page.locator('[data-learning-setting=style]')).toBeVisible();
      await page.locator('[data-learning-action=saveSpeech]').click();
      await page.screenshot({
        path: `artifacts/design22/${platform}-${width}-speech.png`,
        fullPage: true,
      });
      await route('query');
      await page.locator('[data-pronounce]').last().click();
      await page.locator('[data-selection-action=stop]').click();
      await route('cache');
      await expect(page.locator('[data-saved-audio-count]')).toHaveText('2');
      await route('novel');
      await selectText(page, '.prose p,.reading-prose p', 'そっと', false);
      await page.locator('[data-selection-action=query]').click();
      const result = studyResult(page);
      await result.locator('.query-context-detail summary').click();
      await expect(result.locator('.query-context-detail')).toContainText(
        '前文',
      );
      await expect(result.locator('.query-context-detail')).toContainText(
        '后文',
      );
      await expect(result.locator('.query-context-detail')).toContainText(
        '窓を開けると、夏の風がそっと頬に触れた。',
      );
      await result.locator('[data-pronounce="そっと"]').click();
      await page.locator('[data-selection-action=stop]').click();
      await closeStudy(page);
      await route('cache');
      await expect(page.locator('[data-saved-audio-count]')).toHaveText('2');
      await page.locator('[name=textLimit]').selectOption('250');
      await page.locator('[name=audioLimit]').selectOption('2000');
      await page
        .getByRole('button', { name: '保存本机上限', exact: true })
        .click();
      await route('connection');
      await page
        .locator('[data-form=connection] [name=address]')
        .fill('https://cache-test.example');
      await page.locator('[data-form=connection] button[type=submit]').click();
      await route('cache');
      await expect(page.locator('[name=textLimit]')).toHaveValue('100');
      await expect(page.locator('[name=audioLimit]')).toHaveValue('500');
      await expect(page.locator('[data-saved-audio-count]')).toHaveText('0');
      await expect(page.locator('[data-saved-query-count]')).toHaveText('0');
      await route('queryPreferences');
      await expect(budget).toHaveValue('10000');
      expect(
        await page.evaluate(
          () => document.documentElement.scrollWidth > innerWidth + 1,
        ),
      ).toBe(false);
      results.push(
        `${platform}/${width}: budget/default/validation/save, context and image isolation, local clear/service restore, model voices/format/audio variants, full parent sentence, cross-entry word audio reuse, instance settings reset`,
      );
      await page.close();
    }
    expect(errors).toEqual([]);
    fs.writeFileSync(
      'artifacts/design22/results.json',
      JSON.stringify({ results, errors }, null, 2),
    );
    console.log(JSON.stringify({ results, errors }, null, 2));
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
