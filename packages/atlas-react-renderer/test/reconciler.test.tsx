import React from "react";
import { describe, expect, it, vi } from "vitest";
import { createAtlasRoot, type UiNode, type UiPatch } from "../src/index.js";

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

class Sink {
  opened?: UiNode;
  patches: UiPatch[] = [];
  closed = false;
  open(node: UiNode) { this.opened = node; }
  patch(patches: UiPatch[]) { this.patches.push(...patches); }
  close() { this.closed = true; }
}

describe("Atlas React renderer", () => {
  it("emits one keyed text patch for an update", () => {
    const sink = new Sink();
    const root = createAtlasRoot(sink);
    root.render(<text id="status">Old</text>);
    root.render(<text id="status">New</text>);
    expect(sink.patches).toEqual([{ kind: "set-text", id: "status", value: "New" }]);
  });

  it("dispatches actions and cleans up", () => {
    const action = vi.fn();
    const sink = new Sink();
    const root = createAtlasRoot(sink);
    root.render(<button id="run" label="Run" action="run" onAction={action} />);
    root.dispatch({ kind: "button-click", action: "run" });
    root.unmount();
    expect(action).toHaveBeenCalledOnce();
    expect(sink.closed).toBe(true);
  });
});

declare module "react" {
  namespace JSX {
    interface IntrinsicElements {
      text: Record<string, unknown>;
      button: Record<string, unknown>;
    }
  }
}
