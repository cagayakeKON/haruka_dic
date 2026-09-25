const {
  chromium,
  expect,
} = require('../../tools/e2e/node_modules/@playwright/test');
const fs = require('node:fs');

(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const results = [];
  const errors = [];
  fs.mkdirSync('artifacts/design11', { recursive: true });
  try {
    for (const [platform, width] of [
      ['phone', 320],
      ['desktop', 1440],
    ]) {
      const page = await browser.newPage({ viewport: { width, height: 844 } });
      page.on('pageerror', (error) => errors.push(error.message));
      await page.goto(`http://127.0.0.1:8767/${platform}.html#notebooks`);
      const createEmptyBook = async (name) => {
        await page.locator('.book-switcher').click();
        await page.getByRole('button', { name: '新建单词本' }).click();
        await page.getByRole('textbox', { name: '名称' }).fill(name);
        await page.getByRole('dialog').locator('[type="submit"]').click();
        await page
          .locator('[data-x="chooseBook"]')
          .filter({ hasText: name })
          .click();
        await expect(
          page.getByText('这个单词本还没有收藏', { exact: true }),
        ).toBeVisible();
      };
      await createEmptyBook('焦点回归词本');
      await page.locator('.empty [data-x="add"]').click();
      await page
        .locator('[data-x-form="entry"] [name="word"]')
        .fill('新词测试');
      await page
        .locator('[data-x-form="entry"] [name="meaning"]')
        .fill('测试释义');
      await page.locator('[data-x-form="entry"] [type="submit"]').click();
      await expect(
        page.getByRole('dialog').getByRole('heading', { name: '新词测试' }),
      ).toBeVisible();
      await page.keyboard.press('Escape');
      await expect(page.getByRole('dialog')).toHaveCount(0);
      const entry = page.getByRole('button', {
        name: '查看 新词测试',
        exact: true,
      });
      await expect(entry).toBeFocused();
      await entry.press('Space');
      await expect(page.getByRole('dialog')).toBeVisible();
      await page.keyboard.press('Escape');
      await expect(entry).toBeFocused();
      results.push(
        `${platform}/${width}: successful empty-book creation returns to new entry; Space opens details`,
      );
      await createEmptyBook('用于切换的空本');
      await page.locator('.empty [data-x="switch"]').click();
      await page.keyboard.press('Escape');
      await expect(page.getByRole('dialog')).toHaveCount(0);
      await expect(page.locator('.empty [data-x="switch"]')).toBeFocused();
      await page.locator('.empty [data-x="switch"]').click();
      await page.locator('[data-x="chooseBook"][data-id="dailywords"]').click();
      await expect(page.getByRole('dialog')).toHaveCount(0);
      await expect(page.locator('.book-switcher')).toBeFocused();
      await expect(page.locator('.book-switcher')).toContainText('日常的细节');
      results.push(
        `${platform}/${width}: empty-book switch cancellation and success retain focus`,
      );
      await page.close();
    }
    expect(errors).toEqual([]);
    fs.writeFileSync(
      'artifacts/design11/focus-results.json',
      JSON.stringify({ results, errors }, null, 2),
    );
    console.log(
      JSON.stringify({ groups: results.length, results, errors }, null, 2),
    );
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
