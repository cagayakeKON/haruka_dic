const {
  chromium,
  expect,
} = require('../../tools/e2e/node_modules/@playwright/test');
const fs = require('node:fs');

// Local HTML prototype only. All inputs below are fictional test data.
const base = 'http://127.0.0.1:8767/phone.html';
const email = 'mobile-auth@example.test';
const password = 'fictional demo phrase';
const sizes = [
  { width: 320, height: 568 },
  { width: 390, height: 844 },
  { width: 430, height: 932 },
  { width: 390, height: 360 },
  { width: 844, height: 390 },
];

(async () => {
  fs.mkdirSync('artifacts/design7', { recursive: true });
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const page = await browser.newPage({ viewport: sizes[1] });
  page.setDefaultTimeout(10000);
  const errors = [];
  const transportLeaks = [];
  const results = { layouts: [], flows: [] };
  const checkTransport = (value) => {
    if ([email, password].some((secret) => String(value).includes(secret)))
      transportLeaks.push('form data entered transport');
  };
  page.on('pageerror', (error) => errors.push(error.message));
  page.on('request', (request) => {
    checkTransport(request.url());
    checkTransport(request.postData());
  });
  page.on('websocket', (socket) => {
    socket.on('framesent', (frame) => checkTransport(frame.payload));
  });
  async function route(name) {
    await page.goto(`${base}#${name}`);
    await expect(page.locator('.phone-shell')).toHaveAttribute(
      'data-page',
      name,
    );
  }
  async function layout(name) {
    for (const size of sizes) {
      await page.setViewportSize(size);
      await page.evaluate(() => window.scrollTo(0, 0));
      await expect(page.getByRole('heading', { level: 1 })).toHaveCount(1);
      const measure = await page.evaluate(() => ({
        overflow: document.documentElement.scrollWidth > innerWidth + 1,
        brandTop: document.querySelector('.auth-brand').getBoundingClientRect()
          .top,
        targets: [
          ...document.querySelectorAll(
            '.mobile-auth button, .auth-about summary',
          ),
        ].map((el) => ({
          width: el.getBoundingClientRect().width,
          height: el.getBoundingClientRect().height,
        })),
        fonts: [...document.querySelectorAll('.auth-form input')].map((el) =>
          parseFloat(getComputedStyle(el).fontSize),
        ),
      }));
      expect(measure.overflow, `${name}: horizontal overflow`).toBe(false);
      expect(measure.brandTop).toBeLessThan(60);
      for (const target of measure.targets) {
        expect(target.width).toBeGreaterThanOrEqual(44);
        expect(target.height).toBeGreaterThanOrEqual(44);
      }
      for (const font of measure.fonts) expect(font).toBeGreaterThanOrEqual(16);
      const primary = page.locator('.mobile-auth .primary');
      await primary.scrollIntoViewIfNeeded();
      await expect(primary).toBeInViewport({ ratio: 1 });
      const last = page.locator('.mobile-auth button').last();
      await last.scrollIntoViewIfNeeded();
      await expect(last).toBeInViewport({ ratio: 1 });
      results.layouts.push({ page: name, ...size });
    }
    await page.setViewportSize(sizes[1]);
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.screenshot({
      path: `artifacts/design7/${name}.png`,
      fullPage: true,
    });
  }
  try {
    for (const name of ['login', 'register', 'recovery']) {
      await route(name);
      await layout(name);
    }

    await route('login');
    await page.getByRole('button', { name: '登录', exact: true }).click();
    await expect(page.getByLabel('邮箱', { exact: true })).toBeFocused();
    await expect(page.locator('#auth-email-error')).toHaveText('请输入邮箱');
    await expect(page.locator('#auth-password-error')).toHaveText('请输入密码');
    await page.getByLabel('邮箱', { exact: true }).fill('invalid');
    await page.getByLabel('密码', { exact: true }).fill(password);
    await expect(page.locator('#auth-password-error')).toBeHidden();
    await page.getByRole('button', { name: '登录', exact: true }).click();
    await expect(page.locator('#auth-email-error')).toHaveText(
      '请输入有效的邮箱地址',
    );
    await page.getByLabel('邮箱', { exact: true }).fill(email);
    await expect(page.locator('#auth-email-error')).toBeHidden();
    await expect(page.getByLabel('密码', { exact: true })).toHaveAttribute(
      'autocomplete',
      'current-password',
    );
    const reveal = page.getByRole('button', { name: '显示密码', exact: true });
    await reveal.focus();
    await page.keyboard.press('Enter');
    await expect(page.getByLabel('密码', { exact: true })).toHaveAttribute(
      'type',
      'text',
    );
    await expect(
      page.getByRole('button', { name: '隐藏密码', exact: true }),
    ).toHaveAttribute('aria-pressed', 'true');
    await page.getByRole('button', { name: '隐藏密码', exact: true }).click();
    await expect(page.getByLabel('密码', { exact: true })).toHaveValue(
      password,
    );
    await expect(page.getByLabel('密码', { exact: true })).toHaveAttribute(
      'type',
      'password',
    );
    await page.locator('.auth-about summary').click();
    await expect(page.locator('.auth-about p')).toBeVisible();
    await expect(page.getByLabel('密码', { exact: true })).toHaveValue(
      password,
    );
    await page.locator('.auth-about summary').click();
    results.flows.push(
      'login inline validation, keyboard reveal and prototype disclosure',
    );

    await page.getByRole('button', { name: '忘记密码？' }).click();
    await expect(page.getByLabel('邮箱', { exact: true })).toHaveValue(email);
    await page.goBack();
    await expect(page.getByLabel('密码', { exact: true })).toHaveValue('');
    await expect(page.getByLabel('邮箱', { exact: true })).toHaveValue(email);
    await page.getByRole('button', { name: '创建账号', exact: true }).click();
    await page.getByLabel('密码', { exact: true }).fill('short');
    await page.getByLabel('确认密码', { exact: true }).fill('different');
    await page.getByRole('button', { name: '创建账号', exact: true }).click();
    await expect(page.getByLabel('密码', { exact: true })).toBeFocused();
    await expect(page.locator('#auth-password-error')).toHaveText(
      '密码需要 15–128 个字符',
    );
    await expect(page.locator('#auth-confirmPassword-error')).toHaveText(
      '两次输入的密码不一致',
    );
    await page.getByLabel('密码', { exact: true }).fill(password);
    await expect(page.locator('#auth-confirmPassword-error')).toBeHidden();
    await page.getByLabel('确认密码', { exact: true }).fill(password);
    await page
      .getByRole('button', { name: '显示确认密码', exact: true })
      .click();
    await expect(page.getByLabel('确认密码', { exact: true })).toHaveAttribute(
      'type',
      'text',
    );
    await page.getByLabel('确认密码', { exact: true }).press('Enter');
    await expect(page).toHaveURL(/#registrationStatus$/);
    await expect(page.locator('main')).toContainText('尚未创建账号');
    await layout('registrationStatus');
    await page.getByRole('button', { name: '返回登录', exact: true }).click();
    await expect(page.getByLabel('密码', { exact: true })).toHaveValue('');
    await page.getByLabel('密码', { exact: true }).fill(password);
    await page.getByLabel('密码', { exact: true }).press('Enter');
    await expect(page).toHaveURL(/#onboarding$/);
    await page.getByRole('button', { name: '暂时跳过' }).click();
    await expect(page).toHaveURL(/#library$/);
    results.flows.push(
      'registration constraints, acceptance without auto-login, explicit login and skip onboarding',
    );

    await route('login');
    await expect(page.getByLabel('邮箱', { exact: true })).toHaveValue('');
    await page.getByLabel('邮箱', { exact: true }).fill(email);
    await page.getByRole('button', { name: '忘记密码？' }).click();
    await page.getByLabel('邮箱', { exact: true }).press('Enter');
    await expect(page).toHaveURL(/#recoveryStatus$/);
    await expect(page.locator('main')).toContainText('未发送邮件或修改密码');
    await layout('recoveryStatus');
    await page.getByRole('button', { name: '使用其他邮箱' }).click();
    await expect(page).toHaveURL(/#recovery$/);
    await expect(page.getByLabel('邮箱', { exact: true })).toHaveValue(email);
    await page.getByLabel('邮箱', { exact: true }).fill('another@example.test');
    await page.getByRole('button', { name: '提交申请' }).click();
    await page.getByRole('button', { name: '返回登录', exact: true }).click();
    await expect(page).toHaveURL(/#login$/);
    results.flows.push(
      'recovery acceptance, alternate email and return to login',
    );

    // Reload clears local accepted state; a deep link must not invent a result.
    for (const [status, destination] of [
      ['registrationStatus', 'register'],
      ['recoveryStatus', 'recovery'],
    ]) {
      await page.goto(`${base}#${status}`);
      await page.reload();
      await expect(page).toHaveURL(new RegExp(`#${destination}$`));
    }
    results.flows.push('fresh status deep links return to their forms');

    // Resizing represents a short visual viewport, not a physical OS keyboard test.
    await route('register');
    await page.getByLabel('邮箱', { exact: true }).fill(email);
    await page.getByLabel('密码', { exact: true }).fill(password);
    await page.setViewportSize(sizes[3]);
    await page.getByLabel('确认密码', { exact: true }).fill(password);
    await expect(page.getByLabel('密码', { exact: true })).toHaveValue(
      password,
    );
    await page
      .getByRole('button', { name: '创建账号', exact: true })
      .scrollIntoViewIfNeeded();
    await expect(
      page.getByRole('button', { name: '创建账号', exact: true }),
    ).toBeInViewport({ ratio: 1 });
    await page.getByRole('button', { name: '创建账号', exact: true }).click();
    await expect(page).toHaveURL(/#registrationStatus$/);
    results.flows.push('short viewport preserves input and exposes submit');

    await route('login');
    await page.getByRole('button', { name: '服务地址', exact: true }).click();
    await expect(page).toHaveURL(/#connection$/);
    await page.goBack();
    await expect(page).toHaveURL(/#login$/);
    const stored = await page.evaluate(() => ({
      local: localStorage.length,
      session: sessionStorage.length,
    }));
    expect(stored).toEqual({ local: 0, session: 0 });
    expect(transportLeaks).toEqual([]);
    expect(errors).toEqual([]);
    results.flows.push(
      'service address return; no form data in transport or browser storage',
    );
    fs.writeFileSync(
      'artifacts/design7/results.json',
      JSON.stringify(results, null, 2),
    );
    console.log(
      `PASS: ${results.layouts.length} auth layouts, ${results.flows.length} scoped interaction groups; no JS errors.`,
    );
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
