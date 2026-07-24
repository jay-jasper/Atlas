import type { AtlasRoot, UiEvent, UiSink } from "@atlas/react-renderer";
import { createAtlasRoot } from "@atlas/react-renderer";
import type { ReactElement } from "react";
import { unloadHost } from "./host.js";

let root: AtlasRoot | undefined;

export function render(element: ReactElement, sink: UiSink): AtlasRoot {
  root?.unmount();
  root = createAtlasRoot(sink);
  root.render(element);
  return root;
}

export function dispatchUiEvent(event: UiEvent): void {
  root?.dispatch(event);
}

export function unloadRuntime(): void {
  root?.unmount();
  root = undefined;
  unloadHost();
}
