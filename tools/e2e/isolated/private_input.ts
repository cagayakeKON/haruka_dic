import type { Locator } from "@playwright/test";

export async function fillPrivateInput(
  field: Pick<Locator, "fill">,
  value: string,
): Promise<void> {
  try {
    await field.fill(value);
  } catch {
    // Playwright errors include the input value in their call log.
    throw new Error("Private input could not be filled");
  }
}
