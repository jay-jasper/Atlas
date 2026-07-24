import { describe, expect, it } from "vitest";
import { Clipboard, atlasFetch, installHost, type AtlasHost } from "../src/index.js";
describe("capability mapping", () => {
  it("maps clipboard and https requests", async () => {
    const capabilities: string[] = [];
    const fake: AtlasHost = { async request<T>(capability: string): Promise<T> {
      capabilities.push(capability);
      return (capability === "network.https" ? { status: 200, headers: {}, body: "[]" } : undefined) as T;
    }};
    installHost(fake);
    await Clipboard.readText();
    await atlasFetch("https://api.example.com/items");
    expect(capabilities).toEqual(["clipboard.read", "network.https"]);
  });
});
