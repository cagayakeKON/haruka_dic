const {
  chromium,
  expect,
} = require('../../tools/e2e/node_modules/@playwright/test');
const fs = require('node:fs');
const base = 'http://127.0.0.1:8767';
const tabs = {
  library: '材料库',
  notebooks: '单词本',
  query: '查询',
  exercise: '练习',
  settings: '我的',
};

(async () => {
  fs.mkdirSync('artifacts/design9', { recursive: true });
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const errors = [];
  const results = { layouts: [], flows: [] };
  async function newPage(platform, width = 390) {
    const page = await browser.newPage({ viewport: { width, height: 844 } });
    page.setDefaultTimeout(10000);
    page.on('pageerror', (error) =>
      errors.push(`${platform}: ${error.message}`),
    );
    await page.goto(`${base}/${platform}.html#library`);
    return page;
  }
  async function noOverflow(page) {
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth > innerWidth + 1,
      ),
    ).toBe(false);
  }
  try {
    const phone = await newPage('phone');
    for (const width of [320, 390, 735, 1440]) {
      await phone.setViewportSize({ width, height: 844 });
      for (const [route, title] of Object.entries(tabs)) {
        await phone.locator(`.bottom-nav [data-go=${route}]`).click();
        await expect(phone.locator('.phone-head h1')).toHaveText(title);
        await expect(phone.getByRole('heading', { level: 1 })).toHaveCount(1);
        await expect(phone.locator('main h1')).toHaveCount(0);
        await expect(phone.locator('.phone-head')).not.toContainText('haruka');
        await expect(phone.getByRole('searchbox')).toHaveCount(0);
        await noOverflow(phone);
        results.layouts.push({ platform: 'phone', width, route });
      }
    }
    await phone.setViewportSize({ width: 390, height: 844 });
    for (const [route, title] of Object.entries(tabs)) {
      await phone.locator(`.bottom-nav [data-go=${route}]`).click();
      await phone.screenshot({
        path: `artifacts/design9/phone-${route}-final.png`,
        animations: 'disabled',
      });
      await expect(phone.locator('.phone-head h1')).toHaveText(title);
    }
    results.flows.push(
      'phone: five tabs have one header title without duplicate body headings',
    );

    for (const [route, label, term, rows] of [
      ['library', '搜索材料', '夏', '.direct-material'],
      ['notebooks', '搜索收藏', '微笑む', '.collection-row'],
    ]) {
      await phone.locator(`.bottom-nav [data-go=${route}]`).click();
      await phone.getByRole('button', { name: label, exact: true }).click();
      const search = phone.getByRole('searchbox', { name: label });
      await expect(search).toBeFocused();
      const element = await search.elementHandle();
      await search.fill(term);
      expect(
        await element.evaluate(
          (input) => input.isConnected && document.activeElement === input,
        ),
      ).toBe(true);
      await expect(phone.locator(rows)).toHaveCount(1);
      await phone
        .getByRole('button', { name: '清除搜索', exact: true })
        .click();
      await expect(search).toHaveValue('');
      await search.fill(term);
      await phone.goBack();
      await expect(phone.getByRole('searchbox')).toHaveCount(0);
      await expect(
        phone.getByRole('button', { name: label, exact: true }),
      ).toBeFocused();
      await phone.getByRole('button', { name: label, exact: true }).click();
      await expect(search).toHaveValue('');
      await phone.keyboard.press('Escape');
      await expect(phone.getByRole('searchbox')).toHaveCount(0);
      results.flows.push(
        `phone: ${route} search opens, preserves input, clears and closes before route back`,
      );
    }
    await phone.locator('.bottom-nav [data-go=library]').click();
    await phone.locator('[data-filter=textbook]').click();
    await phone.getByRole('button', { name: '搜索材料', exact: true }).click();
    await phone.getByRole('searchbox').fill('夏');
    await expect(phone.locator('.direct-material')).toHaveCount(0);
    await phone.getByRole('button', { name: '关闭搜索' }).click();
    await expect(phone.locator('[data-filter=textbook]')).toHaveAttribute(
      'aria-pressed',
      'true',
    );
    await expect(phone.locator('.direct-material')).toHaveCount(1);
    await phone.locator('[data-filter=all]').click();
    await expect(phone.locator('.floating-action')).toBeVisible();
    await phone.locator('.bottom-nav [data-go=notebooks]').click();
    await phone.getByRole('button', { name: '添加收藏' }).click();
    await expect(phone.getByRole('dialog', { name: '添加收藏' })).toBeVisible();
    await phone.keyboard.press('Escape');
    await expect(phone.getByRole('button', { name: '添加收藏' })).toBeFocused();
    await phone.locator('[data-x=switch]').click();
    await phone.locator('[data-x=chooseBook][data-id=dailywords]').click();
    await expect(phone.getByRole('dialog')).toHaveCount(0);
    await phone.getByRole('button', { name: '搜索收藏', exact: true }).click();
    await phone.getByRole('searchbox').fill('に');
    await expect(phone.locator('.collection-row')).toHaveCount(1);
    await phone.locator('[data-x=entry]').click();
    await expect(phone.getByRole('dialog', { name: '收藏详情' })).toBeVisible();
    await phone.keyboard.press('Escape');
    await expect(phone.getByRole('searchbox')).toHaveValue('に');
    await phone.getByRole('button', { name: '关闭搜索' }).click();
    await expect(phone.locator('.book-switcher')).toContainText('日常');
    results.flows.push(
      'phone: closing search retains type/book; add and entry dialog remain reachable',
    );
    await phone.close();

    for (const platform of ['phone', 'desktop']) {
      const page = await newPage(platform, platform === 'phone' ? 390 : 1440);
      // First visit leaves a real reader entry in browser history.
      await page.locator('[data-material=summer]').click();
      await expect(page).toHaveURL(/#novel$/);
      await page
        .locator(
          platform === 'phone'
            ? '[data-action=back]'
            : '.side-nav [data-go=library]',
        )
        .first()
        .click();
      await expect(page).toHaveURL(/#library$/);
      const more = page.getByRole('button', {
        name: '更多：夏の手紙',
        exact: true,
      });
      await more.focus();
      await page.keyboard.press('Enter');
      await expect(
        page.getByRole('dialog', { name: '材料操作' }),
      ).toBeVisible();
      await page.screenshot({
        path: `artifacts/design9/${platform}-menu-final.png`,
        animations: 'disabled',
      });
      await page.getByRole('button', { name: '查看详情', exact: true }).click();
      await expect(
        page.getByRole('dialog', { name: '材料详情', exact: true }),
      ).toBeVisible();
      await page.keyboard.press('Escape');
      await expect(more).toBeFocused();
      await more.click();
      await page.getByRole('button', { name: '删除', exact: true }).click();
      await expect(
        page.getByRole('dialog', { name: '删除材料', exact: true }),
      ).toContainText('收藏与历史作答保留');
      await page.getByRole('button', { name: '取消', exact: true }).click();
      await expect(
        page.getByRole('dialog', { name: '材料操作' }),
      ).toBeVisible();
      await page.keyboard.press('Escape');
      await expect(page.locator('.direct-material')).toHaveCount(4);
      await more.click();
      await page.getByRole('button', { name: '删除', exact: true }).click();
      await page.getByRole('button', { name: '确认删除', exact: true }).click();
      await expect(page.getByRole('dialog')).toHaveCount(0);
      await expect(page.locator('[data-material=summer]')).toHaveCount(0);
      await expect(page.locator('.direct-material')).toHaveCount(3);
      await expect(
        page.locator('.material-details-button').first(),
      ).toBeFocused();
      await page.evaluate(() => {
        location.hash = 'novel';
      });
      await expect(page).toHaveURL(/#library$/);
      await page
        .locator(
          platform === 'phone'
            ? '.bottom-nav [data-go=notebooks]'
            : '.side-nav [data-go=notebooks]',
        )
        .click();
      await page.locator('[data-x=entry]').first().click();
      await expect(page.getByRole('dialog')).toContainText(
        '原材料已删除，保留收藏快照',
      );
      await expect(page.getByRole('button', { name: /回到原文/ })).toHaveCount(
        0,
      );
      await page.keyboard.press('Escape');
      await page
        .locator(
          platform === 'phone'
            ? '.bottom-nav [data-go=library]'
            : '.side-nav [data-go=library]',
        )
        .click();
      for (const id of ['rain', 'daily', 'n2']) {
        await page.locator(`[data-x=materialActions][data-id=${id}]`).click();
        await page.getByRole('button', { name: '删除', exact: true }).click();
        await page
          .getByRole('button', { name: '确认删除', exact: true })
          .click();
        await expect(page.getByRole('dialog')).toHaveCount(0);
      }
      await expect(page.locator('.direct-material')).toHaveCount(0);
      await expect(page.getByRole('heading', { level: 1 })).toBeFocused();
      await expect(
        page.getByRole('button', { name: '导入材料', exact: true }),
      ).toBeVisible();
      await noOverflow(page);
      for (const removedRoute of [
        'novel',
        'textbook',
        'examPrep',
        'examRun',
        'examResult',
      ]) {
        await page.evaluate((route) => {
          location.hash = route;
        }, removedRoute);
        await expect(page).toHaveURL(/#library$/);
        await expect(page.locator('.direct-material')).toHaveCount(0);
      }
      results.flows.push(
        `${platform}: more menu, details, cancel/confirm deletion, stale reading guard, retained collection snapshots and empty library`,
      );
      await page.close();
    }
    expect(errors).toEqual([]);
    fs.writeFileSync(
      'artifacts/design9/results.json',
      JSON.stringify(results, null, 2),
    );
    console.log(
      `PASS: ${results.layouts.length} tab layouts, ${results.flows.length} interaction groups; no JS errors.`,
    );
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
