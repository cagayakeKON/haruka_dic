/* DESIGN8: library header, mobile import placement and secondary details. */
const {
  chromium,
  expect,
} = require('../../tools/e2e/node_modules/@playwright/test');
const fs = require('node:fs');

(async () => {
  fs.mkdirSync('artifacts/design8', { recursive: true });
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const results = { layouts: [], flows: [] };
  const errors = [];
  try {
    for (const platform of ['phone', 'desktop']) {
      const page = await browser.newPage({
        viewport: { width: platform === 'phone' ? 390 : 1440, height: 844 },
      });
      page.setDefaultTimeout(10000);
      page.on('pageerror', (error) =>
        errors.push(`${platform}: ${error.message}`),
      );
      await page.goto(`http://127.0.0.1:8767/${platform}.html#library`);
      for (const width of [320, 390, 480, 735, 1440]) {
        await page.setViewportSize({ width, height: 844 });
        const measure = await page.evaluate(() => ({
          overflow: document.documentElement.scrollWidth > innerWidth + 1,
          more: [...document.querySelectorAll('.material-details-button')].map(
            (el) => ({
              width: el.getBoundingClientRect().width,
              height: el.getBoundingClientRect().height,
              label: el.textContent,
              separator: getComputedStyle(el).borderLeftWidth,
            }),
          ),
          filters: [...document.querySelectorAll('[data-filter]')].map(
            (el) => el.getBoundingClientRect().top,
          ),
          coverWidth: document
            .querySelector('.direct-material-main .cover')
            .getBoundingClientRect().width,
        }));
        expect(measure.overflow).toBe(false);
        for (const more of measure.more) {
          expect(more.width).toBe(44);
          expect(more.height).toBe(44);
          expect(more.label).toBe('');
          expect(more.separator).toBe('0px');
        }
        await expect(
          page.getByRole('searchbox', { name: '搜索材料' }),
        ).toHaveCount(platform === 'phone' ? 0 : 1);
        if (platform === 'phone') {
          await expect(
            page.locator('.phone-head [data-action=openTabSearch]'),
          ).toHaveCount(1);
          await expect(page.locator('main input[type=search]')).toHaveCount(0);
          expect(new Set(measure.filters).size).toBe(1);
          expect(measure.coverWidth).toBe(54);
          const fab = await page.locator('.floating-action').boundingBox();
          const shell = await page.locator('.phone-shell').boundingBox();
          const nav = await page
            .getByRole('navigation', { name: '主要导航' })
            .boundingBox();
          expect(
            Math.abs(shell.x + shell.width - (fab.x + fab.width) - 20),
          ).toBeLessThan(1);
          expect(fab.y + fab.height).toBeLessThan(nav.y);
        }
        results.layouts.push({ platform, width });
      }
      await page.setViewportSize({
        width: platform === 'phone' ? 390 : 1440,
        height: 844,
      });
      await page.screenshot({
        path: `artifacts/design8/${platform}-library-final.png`,
        fullPage: true,
      });

      const more = page.getByRole('button', {
        name: '更多：夏の手紙',
        exact: true,
      });
      await more.focus();
      await page.keyboard.press('Enter');
      await page.getByRole('button', { name: '查看详情', exact: true }).click();
      await expect(
        page.getByRole('dialog', { name: '材料详情', exact: true }),
      ).toBeVisible();
      await expect(page.getByRole('dialog')).toContainText('夏の手紙');
      await expect(page).toHaveURL(/#library$/);
      await page.keyboard.press('Escape');
      await expect(page.getByRole('dialog')).toHaveCount(0);
      await expect(more).toBeFocused();
      await page.locator('[data-material=summer]').click();
      await expect(page).toHaveURL(/#novel$/);
      await page.goBack();
      await expect(page).toHaveURL(/#library$/);
      results.flows.push(
        `${platform}: secondary details dialog, focus return and direct reading`,
      );

      if (platform === 'phone') {
        await page
          .getByRole('button', { name: '搜索材料', exact: true })
          .click();
        const search = page.getByRole('searchbox', { name: '搜索材料' });
        const originalInput = await search.elementHandle();
        await search.fill('日语');
        expect(
          await originalInput.evaluate(
            (input) => input.isConnected && document.activeElement === input,
          ),
        ).toBe(true);
        await expect(page.locator('.direct-material')).toHaveCount(4);
        await expect(page.locator('.floating-action')).toBeHidden();
        await page
          .getByRole('button', { name: '清除搜索', exact: true })
          .click();
        await expect(search).toHaveValue('');
        await expect(search).toBeFocused();
        await page.locator('[data-filter=textbook]').click();
        await search.fill('夏');
        await expect(page.locator('.direct-material')).toHaveCount(0);
        await page
          .getByRole('button', { name: '清除搜索', exact: true })
          .click();
        await expect(page.locator('[data-filter=textbook]')).toHaveAttribute(
          'aria-pressed',
          'true',
        );
        await expect(page.locator('.direct-material')).toHaveCount(1);
        await page.locator('[data-filter=all]').click();
        await page.getByRole('button', { name: '关闭搜索' }).click();
        await expect(page.locator('.floating-action')).toBeVisible();

        // At the end of the scroll, the last row is above both the FAB and navigation.
        await page.evaluate(() =>
          window.scrollTo(0, document.documentElement.scrollHeight),
        );
        const lastRow = await page
          .locator('.direct-material')
          .last()
          .boundingBox();
        const fab = await page.locator('.floating-action').boundingBox();
        expect(lastRow.y + lastRow.height).toBeLessThan(fab.y);
        await page.locator('.floating-action button').click();
        await expect(page).toHaveURL(/#import$/);
        await expect(
          page.getByRole('heading', { name: '选择类型' }),
        ).toBeVisible();
        await page.locator('[data-import-type=novel]').click();
        await page.getByRole('button', { name: '下一步' }).click();
        await expect(
          page.getByRole('heading', { name: '选择文件' }),
        ).toBeVisible();
        await page.goBack();
        await expect(
          page.getByRole('heading', { name: '选择类型' }),
        ).toBeVisible();
        await page.goBack();
        await expect(page).toHaveURL(/#library$/);
        results.flows.push(
          'phone: stable search input, clear retains type, FAB position and import/back',
        );

        await page
          .getByRole('button', { name: '搜索材料', exact: true })
          .click();
        await search.fill('雨');
        await search.press('Tab');
        await page.locator('[data-material=rain]').click();
        await expect(
          page.getByRole('dialog', { name: '任务进度' }),
        ).toBeVisible();
        await expect
          .poll(
            async () =>
              Number(
                await page
                  .getByRole('dialog')
                  .locator('progress')
                  .first()
                  .getAttribute('value'),
              ),
            { timeout: 15000 },
          )
          .toBeGreaterThan(0);
        await page.keyboard.press('Escape');
        await expect(search).toHaveValue('雨');
        await page
          .getByRole('button', { name: '清除搜索', exact: true })
          .click();
        await page.getByRole('button', { name: '关闭搜索' }).click();
        await page
          .getByRole('button', { name: '站内消息', exact: true })
          .click();
        await expect(page).toHaveURL(/#notifications$/);
        await page.goBack();
        results.flows.push(
          'phone: filtered parsing item still opens live progress; header messages',
        );
      }
      await page.close();
    }
    expect(errors).toEqual([]);
    fs.writeFileSync(
      'artifacts/design8/results.json',
      JSON.stringify(results, null, 2),
    );
    console.log(
      `PASS: ${results.layouts.length} library layouts and ${results.flows.length} scoped interaction groups; no JS errors.`,
    );
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
