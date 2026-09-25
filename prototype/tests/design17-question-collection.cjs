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
  fs.mkdirSync('artifacts/design17', { recursive: true });
  try {
    for (const [platform, width] of [
      ['phone', 320],
      ['phone', 390],
      ['desktop', 390],
      ['desktop', 1440],
    ]) {
      const page = await browser.newPage({ viewport: { width, height: 844 } });
      page.on('pageerror', (error) => errors.push(error.message));
      const route = async (name) => {
        await page.evaluate((name) => {
          location.hash = name;
        }, name);
        await page.waitForTimeout(100);
      };
      const save = page.locator('[data-x=saveQuestion]');
      const confirm = () =>
        page.getByRole('button', { name: '确认收藏', exact: true }).click();
      await page.goto(`http://127.0.0.1:8767/${platform}.html#practice`);
      await save.click();
      await page.getByRole('button', { name: '关闭', exact: true }).click();
      await expect(save).toBeEnabled();
      await save.click();
      await page.locator('[name=books]').first().check();
      await confirm();
      await expect(save).toBeDisabled();
      if (platform === 'phone') {
        await page.goForward();
        await expect(page.getByRole('dialog')).toContainText('这道题已收藏');
        await expect(
          page.getByRole('button', { name: '确认收藏', exact: true }),
        ).toHaveCount(0);
        await page
          .getByRole('button', { name: '返回题目', exact: true })
          .click();
        await expect(page.getByRole('dialog')).toHaveCount(0);
      }
      await expect(
        page.locator('[data-practice-answer][aria-pressed=true]'),
      ).toHaveCount(0);
      await expect(page.locator('.feedback')).toHaveCount(0);
      await route('notebooks');
      const practiceRow = page
        .locator('.collection-row')
        .filter({ hasText: '猫を起こさないように' });
      await expect(practiceRow).toHaveCount(1);
      await practiceRow.locator('button').click();
      await expect(page.locator('.collected-question li')).toHaveCount(4);
      await expect(page.getByRole('dialog')).not.toContainText('参考答案：');
      await expect(page.getByRole('dialog')).not.toContainText('我的作答：');
      await expect(page.getByRole('dialog')).toContainText('作答前收藏');
      await page.getByRole('button', { name: '关闭', exact: true }).click();
      await route('practice');
      await page.locator('[data-practice-answer]').first().click();
      await page.locator('[data-action=practiceSubmit]').click();
      await expect(save).toBeDisabled();
      await route('textbookPractice');
      await page.locator('[data-textbook-answer]').nth(1).click();
      await save.click();
      await confirm();
      await expect(
        page.locator('[data-textbook-answer]').nth(1),
      ).toHaveAttribute('aria-pressed', 'true');
      await expect(page.locator('.feedback')).toHaveCount(0);
      await expect(save).toBeDisabled();
      await route('mistakes');
      await page.locator('[data-mistake]').first().click();
      await page.locator('[data-action=favoriteMistake]').click();
      await expect(page.locator('[data-action=favoriteMistake]')).toContainText(
        '取消收藏',
      );
      await route('examResult');
      await expect(page).toHaveURL(/#examPrep$/);
      await expect(save).toHaveCount(0);
      await expect(page.locator('[data-study-text]')).toHaveCount(0);
      await page.locator('[data-modal=examScript]').click();
      await page.locator('#exam-script-confirm').check();
      await page.locator('[data-action=confirmScript]').click();
      await page.locator('[data-action=examTts]').click();
      await page.locator('[data-action=examFreeze]').click();
      await page.locator('[data-action=examStart]').click();
      await expect(page).toHaveURL(/#examRun$/);
      await expect(save).toHaveCount(0);
      await expect(page.locator('[data-study-text]')).toHaveCount(0);
      await page.locator('[data-exam-answer]').first().click();
      await page.locator('[data-modal=examSubmit]').click();
      await expect(save).toHaveCount(0);
      await page.locator('[data-action=examSubmitConfirm]').click();
      await expect(page).toHaveURL(/#examResult$/);
      await expect(save).toHaveCount(3);
      await expect(page.locator('.exam-review-text')).toHaveCount(3);
      await page.locator('[data-question-id=q1] [data-x=saveQuestion]').click();
      await confirm();
      await expect(
        page.locator('[data-question-id=q1] [data-x=saveQuestion]'),
      ).toBeDisabled();
      await page.locator('[data-question-id=q2] [data-x=saveQuestion]').click();
      await confirm();
      await expect(
        page.locator('[data-question-id=q2] [data-x=saveQuestion]'),
      ).toBeDisabled();
      await selectText(page, '[data-question-id=q1] h4', '穏やか');
      await page.locator('[data-selection-action=read]').click();
      await expect(page.locator('.selection-player')).toContainText('穏やか');
      await page.locator('[data-selection-action=stop]').click();
      await selectText(page, '[data-question-id=q1] h4', '穏やか');
      await page.locator('[data-selection-action=query]').click();
      await expect(page.locator('.selection-query-origin')).toContainText(
        '已交卷复盘',
      );
      await expect(page.locator('[role=dialog] .learning-card')).toContainText(
        '平静的；温和的',
      );
      await page.locator('[data-x=saveCard]').click();
      await confirm();
      await expect(
        page.locator('[role=dialog] [data-x=saveCard]'),
      ).toBeDisabled();
      await page.getByRole('button', { name: '关闭', exact: true }).click();
      await page.screenshot({
        path: `artifacts/design17/${platform}-${width}-review.png`,
        fullPage: true,
        animations: 'disabled',
      });
      await route('notebooks');
      const examRow = page
        .locator('.collection-row')
        .filter({ hasText: '「穏やか」に最接近的意思是？' });
      await expect(examRow).toHaveCount(1);
      await examRow.locator('button').click();
      await expect(page.locator('.collected-question li')).toHaveCount(4);
      await expect(page.getByRole('dialog')).toContainText(
        '我的作答：平静温和',
      );
      await expect(page.getByRole('dialog')).toContainText(
        '参考答案：平静温和',
      );
      await expect(page.getByRole('dialog')).toContainText('N2 模拟试卷');
      await page.screenshot({
        path: `artifacts/design17/${platform}-${width}-collection.png`,
        fullPage: true,
        animations: 'disabled',
      });
      expect(
        await page.evaluate(
          () => document.documentElement.scrollWidth <= innerWidth + 1,
        ),
      ).toBe(true);
      await page.getByRole('button', { name: '关闭', exact: true }).click();
      await practiceRow.locator('button').click();
      await expect(page.getByRole('dialog')).not.toContainText('参考答案：');
      results.push(
        `${platform}/${width}: direct practice/textbook collection; cancel, grouping, dedup, unchanged answers; wrong-history favorite; exam submission gate, correct and unanswered question collection, review speech/query/result collection, full snapshots and no pre-answer leakage`,
      );
      await page.close();
    }
    expect(errors).toEqual([]);
    fs.writeFileSync(
      'artifacts/design17/results.json',
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
