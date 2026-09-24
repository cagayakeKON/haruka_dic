const {
  chromium,
  expect,
} = require('../../tools/e2e/node_modules/@playwright/test');
const fs = require('node:fs');

function contrast(first, second) {
  const luminance = (rgb) => {
    const channels = rgb
      .match(/[\d.]+/g)
      .slice(0, 3)
      .map(Number)
      .map((n) => {
        const s = n / 255;
        return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
      });
    return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
  };
  const values = [luminance(first), luminance(second)].sort((a, b) => b - a);
  return (values[0] + 0.05) / (values[1] + 0.05);
}

(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  const errors = [];
  const results = { transitions: [], contrast: [] };
  page.on('pageerror', (error) => errors.push(error.message));
  async function checkHeading(route) {
    await expect(page).toHaveURL(new RegExp(`#${route}$`));
    const heading = page.getByRole('heading', { level: 1 });
    await expect(heading).toBeFocused();
    await expect(page).toHaveTitle(`${await heading.textContent()} · Haruka`);
    results.transitions.push(route);
    await page.screenshot({
      path: `artifacts/design7/${route}-final.png`,
      fullPage: true,
    });
  }
  try {
    await page.goto('http://127.0.0.1:8767/phone.html#login');
    await checkHeading('login');
    await page.getByRole('button', { name: '创建账号', exact: true }).click();
    await checkHeading('register');
    await page.getByRole('button', { name: '创建账号', exact: true }).click();
    await expect(page.getByLabel('邮箱', { exact: true })).toBeFocused();
    await page.getByLabel('邮箱', { exact: true }).fill('example@example.test');
    await page
      .getByLabel('密码', { exact: true })
      .fill('fictional example phrase');
    await page
      .getByLabel('确认密码', { exact: true })
      .fill('fictional example phrase');
    await page.getByRole('button', { name: '创建账号', exact: true }).click();
    await checkHeading('registrationStatus');
    await page.getByRole('button', { name: '返回登录', exact: true }).click();
    await checkHeading('login');
    await page.getByRole('button', { name: '忘记密码？' }).click();
    await checkHeading('recovery');
    await page.getByRole('button', { name: '提交申请' }).click();
    await checkHeading('recoveryStatus');
    await page.goBack();
    await checkHeading('recovery');
    await page.getByRole('button', { name: '返回登录', exact: true }).click();
    await page.getByRole('button', { name: '服务地址', exact: true }).click();
    await expect(page).toHaveTitle('Haruka · 手机端原型');
    await page.goBack();
    await checkHeading('login');

    for (const theme of ['light', 'dark']) {
      // Exercise the actual theme control, then return to the auth surface.
      // A fresh document restores the prototype sample's signed-in state.
      await page.goto(
        `http://127.0.0.1:8767/phone.html?theme-check=${theme}#appearance`,
      );
      await page.locator('[data-setting=theme]').selectOption(theme);
      await page.evaluate(() => {
        location.hash = 'login';
      });
      await expect(page.locator('.phone-shell')).toHaveAttribute(
        'data-page',
        'login',
      );
      const colors = await page.locator('#auth-email').evaluate((input) => ({
        color: getComputedStyle(input, '::placeholder').color,
        opacity: getComputedStyle(input, '::placeholder').opacity,
        background: getComputedStyle(input.parentElement).backgroundColor,
      }));
      expect(Number(colors.opacity)).toBe(1);
      const ratio = contrast(colors.color, colors.background);
      expect(ratio).toBeGreaterThanOrEqual(4.5);
      results.contrast.push({ theme, ratio });
      await page.screenshot({
        path: `artifacts/design7/login-${theme}-final.png`,
        fullPage: true,
      });
    }
    expect(errors).toEqual([]);
    fs.writeFileSync(
      'artifacts/design7/regressions.json',
      JSON.stringify(results, null, 2),
    );
    console.log(
      `PASS: ${results.transitions.length} heading/title transitions, ${results.contrast.length} placeholder contrast combinations, field error focus retained.`,
    );
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
