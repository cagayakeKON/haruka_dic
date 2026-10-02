import { expect, test } from "@playwright/test";
import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";

test("independent release Web telemetry uses real anonymous ingestion", async ({
  page,
}) => {
  const bundleUrl = process.env.HARUKA_TELEMETRY_BUNDLE_URL;
  if (!bundleUrl)
    throw new Error("Explicit independent telemetry bundle URL required");
  const origin = new URL(test.info().project.use.baseURL as string);
  if (new URL(bundleUrl).origin !== origin.origin)
    throw new Error("Telemetry bundle must share the owned runtime origin");
  const events: {
    event_id: string;
    event: string;
    level: string;
    record_type: string;
    build: string;
    operation_id?: string;
  }[] = [];
  const responses: {
    status: number;
    results: { event_id?: string; status: string }[];
  }[] = [];
  const requests: Promise<void>[] = [];
  page.on("response", (response) => {
    if (new URL(response.url()).pathname !== "/api/v1/frontend-logs/anonymous")
      return;
    requests.push(
      (async () => {
        const payload = response.request().postDataJSON() as {
          events: typeof events;
        };
        for (const event of payload.events)
          events.push({
            event_id: event.event_id,
            event: event.event,
            level: event.level,
            record_type: event.record_type,
            build: event.build,
            ...(event.operation_id ? { operation_id: event.operation_id } : {}),
          });
        const body = (await response.json()) as {
          data: { results: { event_id?: string; status: string }[] };
        };
        responses.push({
          status: response.status(),
          results: body.data.results.map((r) => ({
            ...(r.event_id ? { event_id: r.event_id } : {}),
            status: r.status,
          })),
        });
      })(),
    );
  });
  const output = path.resolve(
    "../../artifacts/stage1/telemetry-release-driver",
  );
  mkdirSync(output, { recursive: true });
  try {
    await page.goto(bundleUrl);
    await expect
      .poll(
        () => ({ events: events.length, responses: responses.length > 0 }),
        {
          timeout: 35_000,
        },
      )
      .toEqual({ events: 5, responses: true });
    await Promise.all(requests);
    expect(events).toHaveLength(5);
    expect(new Set(events.map((e) => e.level))).toEqual(
      new Set(["debug", "info", "warn", "error"]),
    );
    expect(events.some((e) => e.record_type === "performance")).toBe(true);
    expect(events.every((e) => e.build.startsWith("telemetry-pipeline-"))).toBe(
      true,
    );
    expect(responses.length).toBeGreaterThan(0);
    expect(responses.flatMap((r) => r.results)).toHaveLength(5);
    expect(
      responses.every(
        (r) =>
          r.status === 200 && r.results.every((x) => x.status === "accepted"),
      ),
    ).toBe(true);
    await page.screenshot({ path: path.join(output, "driver.png") });
  } finally {
    await Promise.allSettled(requests);
    writeFileSync(
      path.join(output, "network.json"),
      JSON.stringify(
        {
          scope:
            "Independent release test bundle; production main debug emission not claimed",
          events,
          responses,
        },
        null,
        2,
      ),
    );
  }
});
