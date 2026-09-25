const {
  chromium,
  expect,
} = require('../../tools/e2e/node_modules/@playwright/test');
const fs = require('node:fs');

(async () => {
  fs.mkdirSync('artifacts/design11', { recursive: true });
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const results = [];
  const errors = [];
  try {
    for (const [platform, width] of [
      ['phone', 320],
      ['phone', 390],
      ['desktop', 390],
      ['desktop', 1440],
    ]) {
      const page = await browser.newPage({ viewport: { width, height: 844 } });
      page.on('pageerror', (error) =>
        errors.push(`${platform}/${width}: ${error.message}`),
      );
      const base = `http://127.0.0.1:8767/${platform}.html`;
      const navigate = async (route) => {
        const nav = page.locator(
          platform === 'phone' ? '.bottom-nav' : '.side-nav',
        );
        await nav.locator(`[data-go="${route}"]`).click();
      };
      const search = async (label, text) => {
        if (
          platform === 'phone' &&
          !(await page.getByRole('searchbox').count())
        )
          await page.getByRole('button', { name: label, exact: true }).click();
        await page.getByRole('searchbox', { name: label }).fill(text);
        if (platform === 'desktop' && label === '搜索收藏')
          await page.getByRole('button', { name: '搜索', exact: true }).click();
      };
      const noOverflow = async () => {
        expect(
          await page.evaluate(
            () => document.documentElement.scrollWidth <= innerWidth,
          ),
        ).toBe(true);
      };
      await page.goto(base);
      if (platform === 'phone') {
        await page.locator('[data-material="summer"]').click();
        await expect(
          page.getByRole('heading', { name: '窓の向こう' }),
        ).toBeVisible();
        await page.getByRole('button', { name: '返回上一页' }).click();
        await expect(
          page.getByRole('heading', { name: '材料库', exact: true }),
        ).toBeVisible();
        await page.goForward();
        await expect(
          page.getByRole('heading', { name: '窓の向こう' }),
        ).toBeVisible();
        await page.getByRole('button', { name: 'そっと', exact: true }).click();
        await page.getByRole('button', { name: '关闭', exact: true }).click();
        await expect(
          page.getByRole('button', { name: 'そっと', exact: true }),
        ).toBeFocused();
        await page.goBack();
        await expect(
          page.getByRole('heading', { name: '材料库', exact: true }),
        ).toBeVisible();
        results.push(
          `${platform}/${width}: default-entry back/forward and modal return`,
        );
      }
      await page.locator('[data-filter="novel"]').click();
      await expect(page.locator('[data-filter="novel"]')).toBeFocused();
      await search('搜索材料', '  夏  ');
      await expect(page.locator('.direct-material')).toHaveCount(1);
      await search('搜索材料', '不存在的材料');
      await expect(
        page.getByText('没有匹配的材料', { exact: true }),
      ).toBeVisible();
      await page.getByRole('button', { name: '清除搜索与筛选' }).click();
      await expect(page.locator('.direct-material')).toHaveCount(4);
      await expect(page.getByRole('searchbox')).toHaveValue('');
      await expect(page.locator('[data-filter="all"]')).toBeFocused();
      results.push(`${platform}/${width}: material search and filter recovery`);

      await navigate('notebooks');
      const row = page.getByRole('button', {
        name: '查看 微笑む',
        exact: true,
      });
      await row.locator('strong').click();
      await expect(page.getByRole('dialog')).toBeVisible();
      await page.keyboard.press('Escape');
      await expect(page.getByRole('dialog')).toHaveCount(0);
      await expect(row).toBeFocused();
      const position = await page.evaluate(() => scrollY);
      await page.keyboard.press('Enter');
      await expect(page.getByRole('dialog')).toBeVisible();
      await page.keyboard.press('Escape');
      await expect(row).toBeFocused();
      expect(
        Math.abs((await page.evaluate(() => scrollY)) - position),
      ).toBeLessThan(3);
      await page.locator('[data-x="kind"][data-id="phrase"]').click();
      await expect(
        page.locator('[data-x="kind"][data-id="phrase"]'),
      ).toBeFocused();
      await expect(
        page.getByText('当前单词本中还没有短语。', { exact: true }),
      ).toBeVisible();
      await page.getByRole('button', { name: '清除搜索与筛选' }).click();
      await expect(page.locator('.collection-row')).toHaveCount(6);
      await expect(
        page.locator('[data-x="kind"][data-id="all"]'),
      ).toBeFocused();
      await search('搜索收藏', '  ほほえむ  ');
      await expect(page.locator('.collection-row')).toHaveCount(1);
      await search('搜索收藏', '<不存在>');
      await expect(
        page.getByText('没有找到“<不存在>”相关内容。', { exact: true }),
      ).toBeVisible();
      await page.getByRole('button', { name: '清除搜索与筛选' }).click();
      await expect(page.locator('.collection-row')).toHaveCount(6);
      if (platform === 'phone')
        await page
          .getByRole('button', { name: '关闭搜索', exact: true })
          .click();
      await page.locator('[data-x="switch"]').click();
      await page.locator('[data-x="chooseBook"][data-id="dailywords"]').click();
      await expect(page.getByRole('dialog')).toHaveCount(0);
      const bookCount = await page.locator('.collection-row').count();
      expect(bookCount).toBeGreaterThan(0);
      await page.locator('[data-x="kind"][data-id="phrase"]').click();
      await page.getByRole('button', { name: '清除搜索与筛选' }).click();
      await expect(page.locator('.collection-row')).toHaveCount(bookCount);
      await expect(page.locator('.book-switcher')).toContainText('日常的细节');
      await noOverflow();
      await page.screenshot({
        path: `artifacts/design11/${platform}-${width}-collections.png`,
        fullPage: true,
      });
      results.push(
        `${platform}/${width}: whole-row pointer/keyboard, modal focus/scroll, reading search, scoped filter reset`,
      );

      await page.locator('[data-x="switch"]').click();
      await page.getByRole('button', { name: '新建单词本' }).click();
      await page
        .getByRole('textbox', { name: '名称' })
        .fill('窄屏长名称单词本'.repeat(4));
      await page.getByRole('dialog').locator('[type="submit"]').click();
      const emptyBook = page
        .locator('[data-x="chooseBook"]')
        .filter({ hasText: '窄屏长名称' });
      await emptyBook.click();
      await expect(
        page.getByText('这个单词本还没有收藏', { exact: true }),
      ).toBeVisible();
      await noOverflow();
      await page.screenshot({
        path: `artifacts/design11/${platform}-${width}-empty-book.png`,
        fullPage: true,
      });
      await page
        .locator('.empty')
        .getByRole('button', { name: '添加收藏' })
        .click();
      await expect(page.getByRole('dialog')).toBeVisible();
      await page.keyboard.press('Escape');
      await expect(page.locator('.empty [data-x="add"]')).toBeFocused();
      results.push(
        `${platform}/${width}: empty book CTA, long name and no horizontal overflow`,
      );

      if (width === 390) {
        await navigate('library');
        for (const id of ['summer', 'daily', 'n2', 'rain']) {
          await page
            .locator(`[data-x="materialActions"][data-id="${id}"]`)
            .click();
          await page.locator('[data-x="deleteMaterial"]').click();
          await page
            .getByRole('button', { name: '确认删除', exact: true })
            .click();
          await expect(page.getByRole('dialog')).toHaveCount(0);
        }
        await expect(
          page.getByText('材料库还是空的', { exact: true }),
        ).toBeVisible();
        await page
          .locator('.empty')
          .getByRole('button', { name: '导入材料' })
          .click();
        await expect(page.locator('[data-import-type="novel"]')).toBeVisible();
        results.push(
          `${platform}/${width}: genuine empty library to import via UI`,
        );
      }
      await page.close();
    }
    expect(errors).toEqual([]);
    fs.writeFileSync(
      'artifacts/design11/results.json',
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
