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
    for (const width of [320, 390]) {
      const page = await browser.newPage({ viewport: { width, height: 844 } });
      page.on('pageerror', (error) => errors.push(error.message));
      for (const action of ['back', 'builderBack']) {
        // Fresh document/state: no earlier application route to go back to.
        await page.goto('about:blank');
        await page.goto(
          'http://127.0.0.1:8767/phone.html#exerciseBuilder?step=2',
        );
        await page.reload();
        await page.locator(`[data-action=${action}]`).click();
        await expect(page.locator('[data-source=notebook]')).toBeVisible();
        await expect(page.locator('.exercise-builder h1')).toBeFocused();
        await page.locator('[data-action=back]').click();
        await expect(page).toHaveURL(/#exercise$/);
      }
      await page.locator('[data-go=exerciseBuilder]').click();
      await expect(page.locator('.exercise-builder h1')).toBeFocused();
      await page.locator('[data-source=collection]').check();
      await page.locator('[data-practice-collection=smile]').check();
      await page.locator('[data-action=builderNext]').click();
      await page.locator('[data-practice-count]').selectOption('1 题');
      await page.reload();
      await page.locator('[data-action=back]').click();
      await expect(page.locator('[data-source=notebook]')).toBeVisible();
      await page.goForward();
      await expect(page.locator('[data-practice-count]')).toBeVisible();
      await page.locator('[data-action=builderBack]').click();
      await expect(page.locator('[data-source=notebook]')).toBeVisible();
      await page.locator('[data-action=back]').click();
      await expect(page).toHaveURL(/#exercise$/);
      results.push(
        `phone-${width}: fresh/deep-link/reloaded step-two header and edit return stay in flow; entry focus; normal history forward; step-one exit`,
      );
      await page.close();
    }
    expect(errors).toEqual([]);
    fs.mkdirSync('artifacts/design12', { recursive: true });
    fs.writeFileSync(
      'artifacts/design12/navigation.json',
      JSON.stringify(results, null, 2),
    );
    console.log(
      `PASS: ${results.length} targeted navigation groups; no JS errors.`,
    );
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
