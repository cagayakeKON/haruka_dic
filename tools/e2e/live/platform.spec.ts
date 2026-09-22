import { expect, test } from "@playwright/test";
import { ControlsPage } from "../pages/controls.js";

test("SCF-B0-06 formal Web shell registers the administration route", async ({
  page,
}) => {
  const controls = new ControlsPage(page);
  await page.goto("/admin");
  await expect(controls.id("adminPage")).toBeVisible();
  await expect(controls.id("notFoundPage")).toHaveCount(0);
  await controls.id("backHome").click();
  await expect(controls.id("homePage")).toBeVisible();
  await expect(controls.id("adminPage")).toHaveCount(0);
});
