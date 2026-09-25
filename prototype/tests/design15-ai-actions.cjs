const {
  chromium,
  expect,
} = require('../../tools/e2e/node_modules/@playwright/test');
const fs = require('node:fs');
const { selectText } = require('./selection-helpers.cjs');

(async () => {
  fs.mkdirSync('artifacts/design15', { recursive: true });
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const results = [],
    errors = [];
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
      const url = `http://127.0.0.1:8767/${platform}.html`;
      const noChat = async () => {
        await expect(
          page.locator(
            '[data-go=agent], [data-action=askAgent], [data-form=chat], [name=message]',
          ),
        ).toHaveCount(0);
        await expect(page.locator('main')).not.toContainText(
          /问\s*Agent|问学习\s*Agent|学习\s*Agent/,
        );
        expect(
          await page.evaluate(
            () => document.documentElement.scrollWidth <= innerWidth + 1,
          ),
        ).toBe(true);
      };
      const route = async (value) =>
        page.evaluate((value) => {
          location.hash = value;
        }, value);
      await page.goto(`${url}#exercise`);
      await expect(
        page.locator('[data-go=exerciseBuilder]').first(),
      ).toBeVisible();
      await noChat();
      await page.screenshot({
        path: `artifacts/design15/${platform}-${width}-exercise.png`,
        fullPage: true,
      });
      await page.locator('[data-go=report]').click();
      await expect(page.locator('main')).toContainText('学习诊断');
      await noChat();
      await route('exercise');
      await page.locator('[data-go=exerciseBuilder]').first().click();
      await expect(page.locator('[data-source=notebook]')).toBeVisible();
      await noChat();
      await route('novel');
      await selectText(page, '.prose p,.reading-prose p', 'そっと');
      await page.locator('[data-selection-action=query]').click();
      await expect(page.locator('[data-x=saveCard]')).toBeVisible();
      await noChat();
      await page.screenshot({
        path: `artifacts/design15/${platform}-${width}-explanation.png`,
        fullPage: true,
      });
      await page.keyboard.press('Escape');
      await route('query');
      await page.locator('#query-input').fill('そっと');
      await page.locator('#query-input').press('Control+Enter');
      await expect(page.locator('.learning-card').last()).toContainText(
        '轻轻地',
      );
      await noChat();
      results.push(
        `${platform}/${width}: no chat entry; diagnosis, source selection, reading explanation and language query remain available`,
      );

      await route('agent');
      await expect(page).toHaveURL(/#exercise$/);
      await noChat();
      await page.goBack();
      await expect(page).toHaveURL(/#query$/);
      await expect(page.locator('.learning-card').last()).toContainText(
        '轻轻地',
      );
      await page.goForward();
      await expect(page).toHaveURL(/#exercise$/);
      await page.goto(`${url}#agent`);
      await expect(page).toHaveURL(/#exercise$/);
      await noChat();
      results.push(
        `${platform}/${width}: legacy chat deep link and browser history resolve to exercise without restoring chat`,
      );

      if (width === 320 || width === 1440) {
        await route('examPrep');
        await page.locator('[data-modal=examScript]').click();
        await page.locator('#exam-script-confirm').check();
        await page.locator('[data-action=confirmScript]').click();
        await page.locator('[data-action=examTts]').click();
        await page.locator('[data-action=examFreeze]').click();
        await page.locator('[data-action=examStart]').click();
        await expect(page).toHaveURL(/#examRun$/);
        await route('agent');
        await expect(page.getByRole('dialog')).toBeVisible();
        await expect(page).toHaveURL(/#examRun$/);
        await page.keyboard.press('Escape');
        await expect(page.getByRole('dialog')).toHaveCount(0);
        await expect(page).toHaveURL(/#examRun$/);
        results.push(
          `${platform}/${width}: legacy route preserves the active exam leave-confirmation guard`,
        );
      }
      await page.close();
    }
    const admin = await browser.newPage();
    admin.on('pageerror', (error) => errors.push(`admin: ${error.message}`));
    await admin.goto('http://127.0.0.1:8767/desktop.html#adminMenus');
    await admin
      .getByRole('textbox', { name: '登录邮箱' })
      .fill('admin@example.test');
    await admin
      .getByRole('textbox', { name: '密码', exact: true })
      .fill('demo-only-password');
    await admin
      .getByRole('button', { name: '进入管理端演示', exact: true })
      .click();
    await admin.locator('[data-go=adminMenus]').click();
    await expect(admin.locator('main')).toContainText('学习诊断');
    await expect(admin.locator('main')).not.toContainText('学习 Agent');
    await admin.close();
    expect(errors).toEqual([]);
    fs.writeFileSync(
      'artifacts/design15/results.json',
      JSON.stringify(results, null, 2),
    );
    console.log(
      `PASS: ${results.length} scoped groups and admin menu; no JS errors.`,
    );
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
