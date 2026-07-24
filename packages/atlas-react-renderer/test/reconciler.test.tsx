import React, { useState } from "react";
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

  it("publishes state changes caused by a UI event", () => {
    function Switcher() {
      const [url, setUrl] = useState("https://chatgpt.com/");
      return (
        <vstack id="root">
          <button id="gemini" action="gemini" onAction={() => setUrl("https://gemini.google.com/")} />
          <atlas-web-view
            id="browser"
            url={url}
            allowed_hosts={["chatgpt.com", "google.com"]}
          />
        </vstack>
      );
    }
    const sink = new Sink();
    const root = createAtlasRoot(sink);
    root.render(<Switcher />);
    root.dispatch({ kind: "button-click", action: "gemini" });

    expect(sink.patches).toEqual([{
      kind: "replace-node",
      id: "browser",
      node: {
        kind: "web-view",
        id: "browser",
        url: "https://gemini.google.com/",
        allowed_hosts: ["chatgpt.com", "google.com"],
      },
    }]);
  });
});

declare module "react" {
  namespace JSX {
    interface IntrinsicElements {
      text: Record<string, unknown>;
      button: Record<string, unknown>;
      vstack: Record<string, unknown>;
      "atlas-web-view": Record<string, unknown>;
    }
  }
}
