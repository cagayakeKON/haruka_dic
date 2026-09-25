const {
  chromium,
  expect,
} = require('../../tools/e2e/node_modules/@playwright/test');
const { selectText } = require('./selection-helpers.cjs');
const fs = require('node:fs');
(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const results = [],
    errors = [];
  fs.mkdirSync('artifacts/design21', { recursive: true });
  try {
    for (const [width, height, scale] of [
      [3840, 2160, 1],
      [2560, 1440, 1.5],
      [1920, 1080, 2],
      [1280, 900, 1],
      [1024, 768, 1],
    ]) {
      console.log(`Checking desktop ${width}x${height} @${scale}`);
      const page = await browser.newPage({
        viewport: { width, height },
        deviceScaleFactor: scale,
      });
      page.on('pageerror', (error) => errors.push(error.message));
      const panel = page.locator('[data-reader-panel]');
      const body = page.locator('[data-reader-panel-body]');
      const sentence = page.locator('[data-novel-sentence]');
      const closeDialog = () =>
        page.getByRole('button', { name: '关闭', exact: true }).click();
      await page.goto('http://127.0.0.1:8767/desktop.html#novel');
      const readColumns = await page
        .locator('.reader-shell')
        .evaluate(
          (el) => getComputedStyle(el).gridTemplateColumns.split(' ').length,
        );
      expect(readColumns).toBe(width >= 1600 ? 2 : 1);
      await page.locator('[data-mode=analysis]').click();
      await expect(panel).toContainText('点一句');
      await expect(
        page.locator('[role=dialog],.modal-backdrop,[inert]'),
      ).toHaveCount(0);
      await page.locator('[data-novel=prepare]').first().click();
      await page.locator('[data-novel=start]').click();
      await expect(page.locator('[data-novel=start]')).toHaveText(
        '所选内容已就绪',
        { timeout: 12000 },
      );
      await closeDialog();
      await sentence.nth(1).click();
      await expect(panel.locator('.learning-title')).toHaveText(
        '窓を開けると、夏の風がそっと頬に触れた。',
      );
      await expect(
        page.locator('[role=dialog],.modal-backdrop,[inert]'),
      ).toHaveCount(0);
      expect(await page.evaluate(() => document.body.style.overflow)).not.toBe(
        'hidden',
      );
      const geometry = await page.evaluate(() => {
        const rect = (q) =>
          document.querySelector(q).getBoundingClientRect().toJSON();
        return {
          paper: rect('.reading-paper'),
          panel: rect('[data-reader-panel]'),
          shell: rect('.reader-shell'),
          prose: rect('.prose'),
          heading: rect('.reading-paper > h2'),
          columns: getComputedStyle(
            document.querySelector('.reader-shell'),
          ).gridTemplateColumns.split(' ').length,
          overflow: document.documentElement.scrollWidth > innerWidth + 1,
        };
      });
      expect(geometry.overflow).toBe(false);
      expect(geometry.columns).toBe(width >= 1600 ? 3 : width >= 1180 ? 2 : 1);
      expect(geometry.prose.width).toBeLessThanOrEqual(758);
      expect(
        Math.abs(geometry.prose.left - geometry.heading.left),
      ).toBeLessThan(2);
      if (width >= 1180) {
        expect(geometry.panel.left).toBeGreaterThan(geometry.paper.right);
        expect(Math.abs(geometry.panel.top - geometry.paper.top)).toBeLessThan(
          2,
        );
        expect(
          Math.abs(geometry.panel.right - geometry.shell.right),
        ).toBeLessThan(2);
      }
      // No focus trap: reverse tab from the first panel control can reach the source.
      await page.locator('[data-reader-close]').focus();
      await page.keyboard.press('Shift+Tab');
      await expect(sentence.last()).toBeFocused();
      // Nested result goes back to the parent card and its text field.
      await selectText(page, '[data-reader-panel] .learning-title', 'そっと');
      await page.locator('[data-selection-action=query]').click();
      await expect(panel.locator('.learning-title')).toHaveText('そっと');
      await expect(panel.locator('.selection-query-origin')).toContainText(
        '查询结果',
      );
      await page.locator('[data-reader-back]').click();
      await expect(panel.locator('.learning-card-content')).toBeFocused();
      await expect(panel.locator('.learning-title')).toContainText(
        '窓を開けると',
      );
      // Direct source clicks replace the right panel without closing it first.
      await sentence.nth(2).click();
      await expect(panel.locator('.learning-title')).toContainText('机の上');
      await panel.locator('[data-x=saveCard]').click();
      await page.getByRole('button', { name: '确认收藏', exact: true }).click();
      await expect(panel.locator('[data-x=saveCard]')).toBeDisabled();
      await page.getByRole('button', { name: '朗读原句', exact: true }).click();
      await expect(panel.locator('.selection-player')).toBeVisible();
      const audioRect = await panel.locator('.selection-player').boundingBox();
      const panelRect = await panel.boundingBox();
      expect(audioRect.x).toBeGreaterThanOrEqual(panelRect.x);
      expect(audioRect.x + audioRect.width).toBeLessThanOrEqual(
        panelRect.x + panelRect.width,
      );
      await panel.locator('[data-selection-action=pause]').click();
      await page.screenshot({
        path: `artifacts/design21/desktop-${width}-${scale}-panel.png`,
        animations: 'disabled',
      });
      await page.locator('[data-novel=next]').click();
      await expect(panel.locator('.learning-title')).toContainText('見覚え');
      await expect(panel.locator('.selection-player')).toHaveCount(0);
      const cardId = await panel
        .locator('.learning-card')
        .getAttribute('data-card-id');
      // CSS-only reflow preserves the selected card, mode and prepared results.
      await page.setViewportSize({
        width: width >= 1180 ? 1024 : 1920,
        height: 900,
      });
      await expect(panel.locator('.learning-card')).toHaveAttribute(
        'data-card-id',
        cardId,
      );
      await expect(page.locator('[data-mode=analysis]')).toHaveAttribute(
        'aria-pressed',
        'true',
      );
      await expect(
        page.locator('[data-novel-status="2"]').last(),
      ).toContainText('朗读 5/5');
      await page.setViewportSize({ width, height });
      await page.locator('[data-reader-close]').click();
      await expect(panel).toHaveCount(0);
      await expect(sentence.nth(3)).toBeFocused();
      // Opening a genuine preparation dialog from the panel returns to that panel.
      await sentence.nth(1).click();
      await page.locator('[data-novel=prepare]').first().click();
      await closeDialog();
      await expect(panel.locator('.learning-title')).toContainText(
        '窓を開けると',
      );
      await page.locator('[data-selection-action=continuous]').click();
      await expect(
        page.locator('[data-reader-playback] .selection-player'),
      ).toContainText('播放中');
      await sentence.nth(2).click();
      await expect(
        page.locator('[data-reader-playback] .selection-player'),
      ).toContainText('已暂停');
      if (width >= 1600)
        await page.locator('.chapter-nav [data-novel=chapter]').first().click();
      else {
        await page.locator('[data-modal=chapters]').click();
        await page
          .locator('[role=dialog] [data-novel=chapter]')
          .first()
          .click();
      }
      await expect(sentence).toHaveCount(2);
      await expect(panel).toContainText('点一句');
      await expect(page.locator('.selection-player')).toHaveCount(0);
      await page.locator('[data-go=library]').first().click();
      await expect(panel).toHaveCount(0);
      results.push(
        `desktop ${width}x${height} @${scale}: no empty column/overlay; source and panel interaction; nested query/focus, collection, speech, resize, chapter and page cleanup`,
      );
      await page.close();
    }
    expect(errors).toEqual([]);
    fs.writeFileSync(
      'artifacts/design21/results.json',
      JSON.stringify({ results, errors }, null, 2),
    );
    console.log(JSON.stringify({ results, errors }, null, 2));
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
