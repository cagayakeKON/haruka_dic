const {
  chromium,
  expect,
} = require('../../tools/e2e/node_modules/@playwright/test');
const fs = require('node:fs');
const file = {
  name: 'language.png',
  mimeType: 'image/png',
  buffer: Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jXioAAAAASUVORK5CYII=',
    'base64',
  ),
};

(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const results = [],
    errors = [];
  fs.mkdirSync('artifacts/design14', { recursive: true });
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
      const label = `${platform}-${width}`,
        url = `http://127.0.0.1:8767/${platform}.html`;
      const fits = async () =>
        expect(
          await page.evaluate(
            () => document.documentElement.scrollWidth <= innerWidth + 1,
          ),
        ).toBe(true);
      const navigate = async (route) =>
        page
          .locator(
            `${platform === 'phone' ? '.bottom-nav' : '.side-nav'} [data-go=${route}]`,
          )
          .click();
      await page.goto(`${url}#query`);
      await expect(
        page.getByRole('button', { name: '天空为什么是蓝色的？', exact: true }),
      ).toHaveCount(0);
      await expect(
        page.locator('[data-x=queryMode], .query-task-help, .query-task-label'),
      ).toHaveCount(0);
      await fits();
      await page.screenshot({
        path: `artifacts/design14/${label}-query.png`,
        fullPage: true,
      });
      for (const [kind, question, detail] of [
        ['word', 'そっと 是什么意思？', '轻轻握住了手。'],
        ['sentence', '翻译：夏の風がそっと頬に触れた。', '名词 + に + 触れる'],
        ['grammar', 'に 和 へ 有什么区别？', '往车站去，强调方向。'],
        ['exercise', '批改：昨日、図書館に行きます。', '行きました'],
      ]) {
        await page.locator('#query-input').fill(question);
        await page.getByRole('button', { name: '发送问题' }).click();
        const card = page.locator('.learning-card').last();
        await expect(card).toHaveAttribute('data-card-kind', kind);
        await expect(card).toContainText(detail);
        await fits();
        await card.screenshot({
          path: `artifacts/design14/${label}-${kind}.png`,
        });
        await card.locator('[data-x=saveCard]').click();
        await page
          .locator('[data-x-form=saveCard] [name=books]')
          .first()
          .check();
        await page
          .locator('[data-x-form=saveCard] button[type=submit]')
          .click();
        await expect(card.locator('[data-x=saveCard]')).toBeDisabled();
        await expect(card).toBeFocused();
        await card.locator('[data-x=queryAgain]').click();
        await expect(page.locator('#query-input')).toBeFocused();
        const composer = await page.locator('.query-composer').boundingBox();
        const nav = page.locator(
          platform === 'phone' ? '.bottom-nav' : '.side-nav',
        );
        const limit = width < 900 ? (await nav.boundingBox()).y : 844;
        expect(composer.y).toBeGreaterThanOrEqual(60);
        expect(composer.y + composer.height).toBeLessThanOrEqual(limit + 1);
        await navigate('notebooks');
        await page.locator(`[data-x=kind][data-id=${kind}]`).click();
        const saved = page.locator('.collection-row').first();
        await saved.locator('[data-x=entry]').click();
        await expect(page.locator('.entry-detail')).toContainText(detail);
        if (kind !== 'word')
          await expect(page.locator('.entry-detail')).not.toContainText(
            '尚无有效证据',
          );
        await page.keyboard.press('Escape');
        await expect(saved.locator('[data-x=entry]')).toBeFocused();
        await navigate('query');
      }
      results.push(
        `${label}: input automatically routes four samples to typed cards that retain full payload through save, filter and detail; no generic answer kind`,
      );
      await navigate('notebooks');
      await expect(page.locator('[data-x=kind][data-id=answer]')).toHaveCount(
        0,
      );
      await page.locator('[data-x=kind][data-id=word]').click();
      for (const row of await page.locator('.collection-row').all()) {
        const box = await row.boundingBox();
        expect(box.height).toBeGreaterThanOrEqual(44);
        expect(box.height).toBeLessThanOrEqual(82);
      }
      await fits();
      await page.evaluate(() => window.scrollTo(0, 0));
      await page.screenshot({
        path: `artifacts/design14/${label}-notebook.png`,
        fullPage: true,
      });
      await page.locator('[data-x=entry]').first().focus();
      await page.keyboard.press('Enter');
      await expect(page.getByRole('dialog')).toBeVisible();
      await page.keyboard.press('Escape');
      await expect(page.locator('[data-x=entry]').first()).toBeFocused();
      await page.locator('[data-x=kind][data-id=grammar]').click();
      await page.locator('[data-x=entry][data-id=grammar-direction]').click();
      await expect(
        page.locator('.entry-detail .learning-examples'),
      ).toHaveCount(1);
      await expect(page.locator('.entry-detail blockquote')).toHaveCount(0);
      await page.keyboard.press('Escape');
      results.push(
        `${label}: compact 44–82px word rows, complete details, keyboard return and no overflow`,
      );
      await navigate('query');
      const count = await page.locator('.learning-card').count();
      for (const question of [
        '天空为什么是蓝色的？',
        'Write an investment plan',
        'そっと是什么意思？顺便帮我订机票',
      ]) {
        await page.locator('#query-input').fill(question);
        await page.getByRole('button', { name: '发送问题' }).click();
        await expect(page.locator('.learning-card')).toHaveCount(count);
        await expect(page.locator('.query-notice').last()).toContainText(
          '不会回答非语言问题',
        );
      }
      const chooser = page.waitForEvent('filechooser');
      await page.getByRole('button', { name: '添加图片', exact: true }).click();
      await (await chooser).setFiles(file);
      await expect(page.locator('[data-query-images] img')).toHaveCount(1);
      await expect(page.locator('#query-input')).toHaveValue('');
      await expect(
        page.getByRole('button', { name: '发送问题' }),
      ).toBeEnabled();
      await page.getByRole('button', { name: '发送问题' }).click();
      await expect(page.locator('.query-notice').last()).toContainText(
        '图片尚未识别',
      );
      await expect(page.locator('.learning-card')).toHaveCount(count);
      await expect(page.locator('.query-notice [data-x=saveCard]')).toHaveCount(
        0,
      );
      await fits();
      results.push(
        `${label}: non-language requests produce no cards; image-only input can send without choosing a type; unprocessed images cannot be collected`,
      );
      await page.close();
    }
    expect(errors).toEqual([]);
    fs.writeFileSync(
      'artifacts/design14/language.json',
      JSON.stringify(results, null, 2),
    );
    console.log(
      `PASS: ${results.length} language/card/density groups; no JS errors.`,
    );
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
