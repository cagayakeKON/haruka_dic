const {
  chromium,
  expect,
} = require('../../tools/e2e/node_modules/@playwright/test');
const fs = require('node:fs');

(async () => {
  fs.mkdirSync('artifacts/design10', { recursive: true });
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const results = [];
  const errors = [];
  try {
    for (const platform of ['phone', 'desktop']) {
      const page = await browser.newPage({
        viewport: { width: platform === 'phone' ? 390 : 1440, height: 844 },
      });
      page.on('pageerror', (error) =>
        errors.push(`${platform}: ${error.message}`),
      );
      const requests = [];
      page.on('request', (request) => {
        if (!['GET', 'HEAD'].includes(request.method()))
          requests.push(request.url());
      });
      await page.goto(`http://127.0.0.1:8767/${platform}.html?design=10#query`);
      const png = await page.evaluate(() => {
        const canvas = document.createElement('canvas');
        canvas.width = 640;
        canvas.height = 420;
        const ctx = canvas.getContext('2d');
        ctx.fillStyle = '#e8efff';
        ctx.fillRect(0, 0, 640, 420);
        ctx.fillStyle = '#152b42';
        ctx.font = '32px sans-serif';
        ctx.fillText('夏の風がそっと頬に触れた。', 36, 120);
        ctx.font = '24px sans-serif';
        ctx.fillText('「そっと」はどんな意味ですか？', 36, 200);
        return canvas.toDataURL('image/png').split(',')[1];
      });
      const file = {
        name: 'query-example.png',
        mimeType: 'image/png',
        buffer: Buffer.from(png, 'base64'),
      };
      const form = page.locator('[data-x-form=query]');
      const textarea = page.getByRole('textbox', { name: '输入问题' });
      const send = page.getByRole('button', { name: '发送问题' });
      const draftImages = page.locator('[data-query-images] .query-image-tile');
      await expect(send).toBeDisabled();
      await page.locator('[data-x=queryMode][data-id=sentence]').click();
      const chooser = page.waitForEvent('filechooser');
      await page.getByRole('button', { name: '添加图片', exact: true }).click();
      await (await chooser).setFiles([file, { ...file, name: 'second.png' }]);
      await expect(form).toHaveAttribute('aria-busy', 'false');
      await expect(draftImages).toHaveCount(2);
      await expect(send).toBeEnabled();
      await form
        .getByRole('button', { name: '查看图片 1', exact: true })
        .click();
      await expect(
        page.getByRole('dialog', { name: '图片预览' }),
      ).toBeVisible();
      await expect(page.getByRole('dialog').locator('img')).toHaveJSProperty(
        'naturalWidth',
        640,
      );
      await page.keyboard.press('Escape');
      await expect(
        form.getByRole('button', { name: '查看图片 1', exact: true }),
      ).toBeFocused();
      await form
        .getByRole('button', { name: '移除图片 2', exact: true })
        .click();
      await expect(draftImages).toHaveCount(1);
      await expect(textarea).toBeFocused();
      for (const width of platform === 'phone'
        ? [320, 390, 735]
        : [390, 1440]) {
        await page.setViewportSize({ width, height: 844 });
        expect(
          await page.evaluate(
            () => document.documentElement.scrollWidth <= innerWidth,
          ),
        ).toBe(true);
        for (const button of await form.locator('button:visible').all()) {
          const box = await button.boundingBox();
          expect(box.width).toBeGreaterThanOrEqual(44);
          expect(box.height).toBeGreaterThanOrEqual(44);
        }
        const box = await send.boundingBox();
        if (platform === 'phone') {
          const nav = await page.locator('.bottom-nav').boundingBox();
          expect(box.y + box.height).toBeLessThanOrEqual(nav.y);
        }
        results.push(
          `${platform} ${width}: attachment layout and 44px actions`,
        );
      }
      await page.setViewportSize({
        width: platform === 'phone' ? 390 : 1440,
        height: 844,
      });
      await page.screenshot({
        path: `artifacts/design10/${platform}-draft.png`,
        animations: 'disabled',
      });
      await send.click();
      await expect(draftImages).toHaveCount(0);
      await expect(page.locator('.query-question img')).toHaveCount(1);
      await expect(page.locator('.query-notice').last()).toContainText(
        '图片尚未识别',
      );
      await expect(send).toBeDisabled();
      // Paste goes through the same browser event handler; never read the user's OS clipboard.
      await textarea.fill('解释：');
      const original = await textarea.elementHandle();
      await textarea.evaluate((input, data) => {
        input.setSelectionRange(input.value.length, input.value.length);
        const clipboardData = new DataTransfer();
        clipboardData.items.add(
          new File(
            [Uint8Array.from(atob(data), (c) => c.charCodeAt(0))],
            'clipboard.png',
            { type: 'image/png' },
          ),
        );
        clipboardData.setData('text/plain', 'そっと');
        input.dispatchEvent(
          new ClipboardEvent('paste', {
            clipboardData,
            bubbles: true,
            cancelable: true,
          }),
        );
      }, png);
      await expect(draftImages).toHaveCount(1);
      await expect(textarea).toHaveValue('解释：そっと');
      expect(await original.evaluate((input) => input.isConnected)).toBe(true);
      const navPrefix = platform === 'phone' ? '.bottom-nav' : '.side-nav';
      await page.locator(`${navPrefix} [data-go=library]`).click();
      await page.locator(`${navPrefix} [data-go=query]`).click();
      await expect(draftImages).toHaveCount(1);
      await expect(textarea).toHaveValue('解释：そっと');
      await send.click();
      await expect(page.locator('.query-notice').last()).toContainText(
        '图片尚未识别',
      );
      await expect(page.locator('.query-question').last()).toContainText(
        '解释：そっと',
      );
      await page.screenshot({
        path: `artifacts/design10/${platform}-sent.png`,
        animations: 'disabled',
      });
      const input = page.locator('[data-query-file=album]');
      await input.setInputFiles(file);
      await expect(draftImages).toHaveCount(1);
      await input.setInputFiles(file);
      await expect(draftImages).toHaveCount(2);
      await input.setInputFiles([file, file, file]);
      await expect(page.locator('[data-query-error]')).toContainText(
        '最多添加 4',
      );
      await expect(draftImages).toHaveCount(2);
      for (const invalid of [
        {
          name: 'fake.svg',
          mimeType: 'image/svg+xml',
          buffer: Buffer.from('<svg/>'),
        },
        {
          name: 'oversize.png',
          mimeType: 'image/png',
          buffer: Buffer.alloc(10_000_001),
        },
        {
          name: 'broken.png',
          mimeType: 'image/png',
          buffer: Buffer.from('broken'),
        },
      ]) {
        await input.setInputFiles(invalid);
        await expect(form).toHaveAttribute('aria-busy', 'false');
        await expect(page.locator('[data-query-error]')).toBeVisible();
        await expect(draftImages).toHaveCount(2);
      }
      if (platform === 'phone') {
        const camera = page.locator('[data-query-file=camera]');
        await expect(camera).toHaveAttribute('capture', 'environment');
        const capture = page.waitForEvent('filechooser');
        await page.getByRole('button', { name: '拍照', exact: true }).click();
        await (await capture).setFiles({ ...file, name: 'camera.jpg.png' });
        await expect(draftImages).toHaveCount(3);
      } else
        await expect(
          page.getByRole('button', { name: '拍照', exact: true }),
        ).toHaveCount(0);
      await page.evaluate(() => {
        location.hash = 'security';
      });
      await page.locator('[data-action=logout]').click();
      await expect(page).toHaveURL(/#login$/);
      // Login is the existing local demo, not an authentication bypass added by this test.
      await page.locator('input[type=email]').fill('test@example.test');
      await page
        .locator('input[type=password]')
        .first()
        .fill('DemoPassword123');
      await page.locator('form button[type=submit]').click();
      await page.locator(`${navPrefix} [data-go=query]`).click();
      await expect(draftImages).toHaveCount(0);
      await expect(page.locator('.query-question')).toHaveCount(0);
      await textarea.fill('そっと 是什么意思？');
      await send.click();
      await expect(page.locator('.learning-card')).toContainText('轻轻地');
      expect(requests).toEqual([]);
      results.push(
        `${platform}: file/preview/remove/image-only/mixed paste/draft/error/camera-input/logout/text-only; no upload requests`,
      );
      await page.close();
    }
    expect(errors).toEqual([]);
    fs.writeFileSync(
      'artifacts/design10/results.json',
      JSON.stringify(results, null, 2),
    );
    console.log(
      `PASS: ${results.length} scoped groups; no JS errors or upload requests.`,
    );
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
