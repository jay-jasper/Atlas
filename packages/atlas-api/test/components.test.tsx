import React from "react";
import { describe, expect, it } from "vitest";
import { Action, ActionPanel, List, render } from "../src/index.js";
import type { UiNode } from "@atlas/react-renderer";
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
describe("components", () => {
  it("renders a searchable list with an action", () => {
    let tree: UiNode | undefined;
    const root = render(<List searchBarPlaceholder="Search"><List.Item id="one" title="One" actions={<ActionPanel><Action id="copy" title="Copy" /></ActionPanel>} /></List>, {
      open(node) { tree = node; }, patch() {}, close() {},
    });
    expect(tree?.kind).toBe("list");
    expect(tree?.children?.[0]?.id).toBe("one");
    root.unmount();
  });
});
