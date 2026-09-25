// Drive the browser's real text selection, without changing application state.
async function selectText(page, selector, text, touch = false) {
  const target = page.locator(selector).filter({ hasText: text }).first();
  await target.scrollIntoViewIfNeeded();
  const points = await target.evaluate((el, text) => {
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
      const offset = node.textContent.indexOf(text);
      if (offset < 0) continue;
      const first = document.createRange(),
        last = document.createRange();
      first.setStart(node, offset);
      first.setEnd(node, offset + 1);
      last.setStart(node, offset + text.length - 1);
      last.setEnd(node, offset + text.length);
      const a = first.getBoundingClientRect(),
        b = last.getBoundingClientRect();
      return {
        x: a.x + 1,
        y: a.y + a.height / 2,
        endX: b.right - 1,
        endY: b.y + b.height / 2,
      };
    }
    throw new Error(`Text not found: ${text}`);
  }, text);
  if (touch) {
    const client = await page.context().newCDPSession(page);
    await client.send("Input.dispatchTouchEvent", {
      type: "touchStart",
      touchPoints: [{ x: points.x, y: points.y }],
    });
    await page.waitForTimeout(650);
    await client.send("Input.dispatchTouchEvent", {
      type: "touchEnd",
      touchPoints: [],
    });
    await client.detach();
  } else {
    await page.mouse.move(points.x, points.y);
    await page.mouse.down();
    await page.mouse.move(points.endX, points.endY, { steps: 12 });
    await page.mouse.up();
  }
}
module.exports = { selectText };
