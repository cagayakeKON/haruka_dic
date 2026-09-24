const {
  chromium,
  expect,
} = require('../../tools/e2e/node_modules/@playwright/test');
const fs = require('node:fs');
const file = {
  name: 'sample.png',
  mimeType: 'image/png',
  buffer: Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jXioAAAAASUVORK5CYII=',
    'base64',
  ),
};
(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const results = [],
    errors = [];
  try {
    for (const platform of ['phone', 'desktop']) {
      const page = await browser.newPage({
        viewport: { width: platform === 'phone' ? 390 : 1440, height: 844 },
      });
      page.on('pageerror', (e) => errors.push(e.message));
      await page.goto(`http://127.0.0.1:8767/${platform}.html#query`);
      let picker = page.waitForEvent('filechooser');
      await page.getByRole('button', { name: '添加图片', exact: true }).click();
      await (await picker).setFiles(file);
      await expect(page.locator('[data-query-images] img')).toHaveCount(1);
      await expect(page.locator('#query-input')).toBeFocused();
      results.push(`${platform}: picker completion restores composer focus`);

      await page.addInitScript(() => {
        const read = Blob.prototype.arrayBuffer;
        Blob.prototype.arrayBuffer = async function () {
          const value = await read.call(this);
          if (this.size === 12)
            await new Promise((resolve) => {
              window.releaseHeader = resolve;
            });
          return value;
        };
        window.createdImageUrls = 0;
        const create = URL.createObjectURL;
        URL.createObjectURL = function (blob) {
          window.createdImageUrls++;
          return create.call(this, blob);
        };
      });
      await page.reload();
      picker = page.waitForEvent('filechooser');
      await page.getByRole('button', { name: '添加图片', exact: true }).click();
      await (await picker).setFiles(file);
      await page.waitForFunction(
        () => typeof window.releaseHeader === 'function',
      );
      const differentFocus = page.getByRole('button', {
        name: '站内消息',
        exact: true,
      });
      await differentFocus.focus();
      await page.evaluate(() => window.releaseHeader());
      await expect(page.locator('[data-query-images] img')).toHaveCount(1);
      await expect(differentFocus).toBeFocused();
      results.push(
        `${platform}: asynchronous completion does not steal a new focus target`,
      );

      await page.reload();
      await page.locator('[data-query-file=album]').setInputFiles(file);
      await page.waitForFunction(
        () => typeof window.releaseHeader === 'function',
      );
      await page.evaluate(() => {
        location.hash = 'security';
      });
      await page.locator('[data-action=logout]').click();
      await expect(page).toHaveURL(/#login$/);
      await page.evaluate(async () => {
        window.releaseHeader();
        await new Promise((resolve) =>
          requestAnimationFrame(() => requestAnimationFrame(resolve)),
        );
      });
      expect(await page.evaluate(() => window.createdImageUrls)).toBe(0);
      await expect(page.locator('[data-query-images]')).toHaveCount(0);
      results.push(
        `${platform}: delayed file header cannot create an image URL after logout`,
      );
      await page.close();
    }
    expect(errors).toEqual([]);
    fs.writeFileSync(
      'artifacts/design10/regressions.json',
      JSON.stringify(results, null, 2),
    );
    console.log(
      `PASS: ${results.length} focused regression groups; no JS errors.`,
    );
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
