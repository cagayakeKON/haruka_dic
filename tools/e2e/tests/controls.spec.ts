import { test, expect } from "@playwright/test";
import { ControlsPage } from "../pages/controls.js";

for (const audience of ["client", "admin"]) {
  test(`UIE-03 ${audience}: external semantics edit/dialog/list/resize/refresh`, async ({
    page,
  }) => {
    const controls = new ControlsPage(page);
    const base = audience === "admin" ? "/admin/fixture" : "/fixture";
    await page.goto(base);
    await expect(controls.id("fixturePage")).toHaveCount(1);
    await expect(controls.input()).toHaveAccessibleName("原型输入");
    await expect(
      controls.id("fixtureSubmit").getByRole("button"),
    ).toBeDisabled();
    await controls.edit("Haruka browser sample");
    await page.setViewportSize({ width: 390, height: 844 });
    await expect(controls.input()).toHaveValue("Haruka browser sample");
    await controls.id("fixtureSubmit").click();
    await expect(controls.id("fixtureDialog")).toBeVisible();
    await controls.id("fixtureConfirm").click();
    await expect(controls.id("fixtureDialog")).toHaveCount(0);
    await expect(
      page.getByText("已确认：Haruka browser sample", { exact: true }),
    ).toBeVisible();
    const list = controls.id("fixtureList");
    await list.hover();
    for (
      let attempt = 0;
      attempt < 12 && (await controls.id("fixtureLastRow").count()) === 0;
      attempt++
    )
      await page.mouse.wheel(0, 900);
    await expect(controls.id("fixtureLastRow")).toBeVisible();
    await controls.id("fixtureNavigate").click();
    await expect(page).toHaveURL(`${base}/next`);
    await page.reload();
    await expect(controls.id("backHome")).toBeVisible();
    await controls.id("backHome").click();
    await expect(controls.id("fixturePage")).toBeVisible();
  });
}

test("SCF-B0-06 missing assets and API paths never use SPA fallback", async ({
  request,
}) => {
  for (const path of ["/api/v1/missing", "/assets/missing.js"]) {
    const response = await request.get(path);
    expect(response.status()).toBe(404);
    expect(response.headers()["content-type"]).toBe("text/plain");
  }
});
