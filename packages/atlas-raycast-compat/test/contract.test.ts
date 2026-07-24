import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";
import * as exports from "../src/index.js";
describe("Raycast compatibility contract", () => {
  it("exports every supported matrix symbol", async () => {
    const matrix = JSON.parse(await readFile(new URL("../../../compat/raycast/matrix.json", import.meta.url), "utf8")) as {
      symbols: Array<{ name: string; status: string }>;
    };
    for (const entry of matrix.symbols.filter(({ status }) => status !== "unsupported")) {
      expect(exports[entry.name as keyof typeof exports], entry.name).toBeDefined();
    }
  });
  it("unsupported APIs fail explicitly", () => {
    expect(() => exports.openExtensionPreferences()).toThrow(/unsupported/);
  });
});
