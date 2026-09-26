import { readFileSync } from "node:fs";
import { expect, type Locator, type Page } from "@playwright/test";

const parsed: unknown = JSON.parse(
  readFileSync(
    new URL("../../../frontend/config/ui_test_ids.json", import.meta.url),
    "utf8",
  ),
);
if (
  typeof parsed !== "object" ||
  parsed === null ||
  !("static" in parsed) ||
  typeof parsed.static !== "object" ||
  parsed.static === null
)
  throw new Error("Invalid UI registry");
const registry = new Map<string, string>();
for (const [key, value] of Object.entries(parsed.static)) {
  if (
    typeof value !== "string" ||
    !/^(client|admin)(\.[a-z][a-z0-9_]*){3}$/.test(value) ||
    [...registry.values()].includes(value)
  )
    throw new Error("Invalid UI identifier");
  registry.set(key, value);
}

export class ControlsPage {
  constructor(readonly page: Page) {}

  id(key: string): Locator {
    const value = registry.get(key);
    if (!value) throw new Error("Unregistered UI identifier");
    return this.page.getByTestId(value);
  }

  // The registered test ID wraps the real editable input.
  input(): Locator {
    return this.id("fixtureInput").locator("input, textarea");
  }

  async edit(text: string): Promise<void> {
    await this.input().click();
    await expect(this.input()).toBeFocused();
    await this.input().pressSequentially(text);
    await expect(this.input()).toHaveValue(text);
    await expect(this.input()).toBeFocused();
  }
}
