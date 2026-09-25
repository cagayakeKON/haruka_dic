const {
  chromium,
  expect,
} = require('../../tools/e2e/node_modules/@playwright/test');
const fs = require('node:fs');
(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const errors = [],
    results = [];
  try {
    for (const [platform, width] of [
      ['phone', 320],
      ['desktop', 1440],
    ]) {
      const page = await browser.newPage({ viewport: { width, height: 844 } });
      page.on('pageerror', (error) => errors.push(error.message));
      const url = `http://127.0.0.1:8767/${platform}.html`;
      await page.goto(`${url}#notebooks`);
      await page.locator('[data-x=add]').click();
      const word = '長い見出し'.repeat(20) + '<b>原样保留</b>';
      const meaning = '完整释义'.repeat(40);
      await page.locator('[data-x-form=entry] [name=word]').fill(word);
      await page.locator('[data-x-form=entry] [name=meaning]').fill(meaning);
      await page.locator('[data-x-form=entry] button[type=submit]').click();
      await expect(page.locator('.entry-detail h2')).toHaveText(word);
      await expect(
        page.locator('.entry-detail .learning-definition'),
      ).toContainText(meaning);
      await expect(page.locator('.entry-detail h2 b')).toHaveCount(0);
      await page.keyboard.press('Escape');
      const row = page.locator('.collection-row').first();
      expect((await row.boundingBox()).height).toBeLessThanOrEqual(82);
      expect(
        await page.evaluate(
          () => document.documentElement.scrollWidth <= innerWidth + 1,
        ),
      ).toBe(true);
      await row.locator('[data-x=entry]').click();
      await expect(page.locator('.entry-detail h2')).toHaveText(word);
      await page.keyboard.press('Escape');
      await page.goto(`${url}#appearance`);
      await page.locator('[data-setting=theme]').selectOption('dark');
      await page.goto(`${url}#query`);
      await page
        .getByRole('button', { name: 'そっと 是什么意思？', exact: true })
        .click();
      await page.getByRole('button', { name: '发送问题' }).click();
      await expect(page.locator('body')).toHaveAttribute('data-theme', 'dark');
      await expect(page.locator('.learning-card')).toContainText('轻轻地');
      await page.locator('.learning-card').screenshot({
        path: `artifacts/design13/${platform}-${width}-dark.png`,
      });
      results.push(
        `${platform}-${width}: long summaries stay compact while details retain literal full text; dark-theme card rendering`,
      );
      await page.close();
    }
    expect(errors).toEqual([]);
    fs.writeFileSync(
      'artifacts/design13/boundaries.json',
      JSON.stringify(results, null, 2),
    );
    console.log(`PASS: ${results.length} boundary groups; no JS errors.`);
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
