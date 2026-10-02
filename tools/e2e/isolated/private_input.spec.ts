import { expect, test } from "@playwright/test";
import { randomUUID } from "node:crypto";
import { fillPrivateInput } from "./private_input.js";

test("private input keeps successful fills and discards secret-bearing failures", async () => {
  const sentinel = `synthetic-private-input-${randomUUID()}`;
  let successfulCalls = 0;
  await fillPrivateInput(
    {
      fill: (value) => {
        successfulCalls++;
        expect(value === sentinel).toBe(true);
        return Promise.resolve();
      },
    },
    sentinel,
  );
  expect(successfulCalls).toBe(1);

  let failedCalls = 0;
  let observed: unknown;
  try {
    await fillPrivateInput(
      {
        fill: (value) => {
          failedCalls++;
          const error = new Error(`locator.fill: Timeout; fill("${value}")`);
          error.cause = { callLog: value };
          return Promise.reject(error);
        },
      },
      sentinel,
    );
  } catch (error) {
    observed = error;
  }
  expect(failedCalls).toBe(1);
  expect(observed).toBeInstanceOf(Error);
  if (!(observed instanceof Error))
    throw new Error("Expected sanitized failure");
  expect(observed.message).toBe("Private input could not be filled");
  expect(observed.cause).toBeUndefined();
  const report = `${observed.stack ?? ""}${JSON.stringify(observed)}`;
  expect(report.includes(sentinel)).toBe(false);
});
