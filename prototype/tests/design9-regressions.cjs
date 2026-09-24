const {
  chromium,
  expect,
} = require('../../tools/e2e/node_modules/@playwright/test');
const fs = require('node:fs');

(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const errors = [];
  const results = [];
  const settleHistory = (page) =>
    page.evaluate(
      () =>
        new Promise((resolve) =>
          requestAnimationFrame(() => requestAnimationFrame(resolve)),
        ),
    );
  try {
    const phone = await browser.newPage({
      viewport: { width: 390, height: 844 },
    });
    phone.on('pageerror', (error) => errors.push(error.message));
    await phone.goto('http://127.0.0.1:8767/phone.html#library');
    for (const [route, label, term] of [
      ['library', '搜索材料', '夏'],
      ['notebooks', '搜索收藏', '微笑む'],
    ]) {
      await phone.locator(`.bottom-nav [data-go=${route}]`).click();
      await phone.getByRole('button', { name: label, exact: true }).click();
      await phone.getByRole('searchbox').fill(term);
      await phone.goBack();
      await settleHistory(phone);
      await expect(
        phone.getByRole('button', { name: label, exact: true }),
      ).toBeFocused();
      await phone.goForward();
      await settleHistory(phone);
      await expect(phone.getByRole('searchbox')).toBeFocused();
      await phone.getByRole('searchbox').fill(term);
      await phone.locator('.bottom-nav [data-go=query]').click();
      await phone.goBack();
      await settleHistory(phone);
      await expect(phone.getByRole('searchbox')).toBeFocused();
      await expect(phone.getByRole('searchbox')).toHaveValue(term);
      await phone
        .getByRole('button', { name: '关闭搜索', exact: true })
        .click();
      await expect(phone.getByRole('searchbox')).toHaveCount(0);
      await phone.locator('.bottom-nav [data-go=query]').click();
      await phone.goBack();
      await settleHistory(phone);
      await expect(phone.locator('.root-head h1')).toBeFocused();
      results.push(
        `${route}: history forward/search return and tab heading retain focus`,
      );
    }
    await phone.locator('.bottom-nav [data-go=library]').click();
    await phone.getByRole('button', { name: '搜索材料', exact: true }).click();
    await phone.getByRole('searchbox').fill('夏');
    await phone.locator('[data-x=materialActions][data-id=summer]').click();
    await phone.getByRole('button', { name: '删除', exact: true }).click();
    await phone.getByRole('button', { name: '确认删除', exact: true }).click();
    await expect(phone.getByRole('dialog')).toHaveCount(0);
    await settleHistory(phone);
    await expect(phone.locator('.direct-material')).toHaveCount(0);
    await expect(phone.getByRole('searchbox')).toBeFocused();
    results.push(
      'phone: deleting the only search match returns focus to search',
    );
    await phone.close();

    for (const platform of ['phone', 'desktop']) {
      const page = await browser.newPage({
        viewport: { width: platform === 'phone' ? 390 : 1440, height: 844 },
      });
      page.on('pageerror', (error) => errors.push(error.message));
      await page.goto(`http://127.0.0.1:8767/${platform}.html#exerciseBuilder`);
      for (const checkbox of await page.locator('[data-source]').all()) {
        await checkbox.setChecked(
          (await checkbox.getAttribute('data-source')) === 'textbook',
        );
      }
      await page.locator('[data-action=builderNext]').click();
      await page.locator('[data-action=practicePreview]').click();
      await expect(page.locator('main')).toContainText(/4 项/);
      await page.evaluate(() => {
        location.hash = 'library';
      });
      await page.locator('[data-x=materialActions][data-id=daily]').click();
      await page.getByRole('button', { name: '删除', exact: true }).click();
      await page.getByRole('button', { name: '确认删除', exact: true }).click();
      await expect(page.getByRole('dialog')).toHaveCount(0);
      await page.evaluate(() => {
        location.hash = 'exerciseBuilder';
      });
      await expect(page.locator('[data-source=textbook]')).toBeDisabled();
      await expect(page.locator('[data-source=textbook]')).not.toBeChecked();
      await expect(page.locator('[data-practice-unit]')).toHaveCount(0);
      await expect(page.locator('[data-action=builderNext]')).toBeDisabled();
      await expect(page.locator('main')).toContainText(/暂无可用/);
      await page.locator('[data-source=mistake]').check();
      await expect(page.locator('[data-action=builderNext]')).toBeEnabled();
      results.push(
        `${platform}: deleted textbook clears selected source/preview; unavailable for new tasks; mistake history remains selectable`,
      );
      await page.close();
    }
    expect(errors).toEqual([]);
    fs.mkdirSync('artifacts/design9', { recursive: true });
    fs.writeFileSync(
      'artifacts/design9/regressions.json',
      JSON.stringify(results, null, 2),
    );
    console.log(
      `PASS: ${results.length} focused regression groups; no JS errors.`,
    );
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
