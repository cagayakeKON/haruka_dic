import { expect, test } from "@playwright/test";
import { ControlsPage } from "../pages/controls.js";

test("SCF-B0-05 real API readiness is decoded after an explicit UI action", async ({
  page,
}) => {
  const controls = new ControlsPage(page);
  let requests = 0;
  page.on("request", (request) => {
    if (new URL(request.url()).pathname === "/health/ready") requests += 1;
  });
  await page.goto("/environment");
  await expect(controls.id("environmentPage")).toBeVisible();
  await expect(controls.id("checkConnection")).toBeVisible();
  expect(requests).toBe(0);
  await expect(controls.id("connectionStatus")).toHaveCount(0);

  const received = page.waitForResponse(
    (response) =>
      response.url() === "http://127.0.0.1:18080/health/ready" &&
      response.request().method() === "GET",
  );
  await controls.id("checkConnection").click();
  const response = await received;
  expect(response.status()).toBe(200);
  expect(response.headers()["content-type"]).toContain("application/json");
  expect(response.headers()["access-control-allow-origin"]).toBe(
    "http://localhost:5173",
  );
  const payload: unknown = await response.json();
  expect(payload).toMatchObject({ data: { status: "ok" } });
  await expect(controls.id("connectionStatus")).toContainText("服务已就绪");
  expect(requests).toBe(1);
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(controls.id("connectionStatus")).toContainText("服务已就绪");
  expect(requests).toBe(1);
});
