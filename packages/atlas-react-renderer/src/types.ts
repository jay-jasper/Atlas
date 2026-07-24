import type { ReactElement } from "react";

export type UiNodeKind =
  | "vstack" | "hstack" | "section" | "list" | "list-item" | "detail"
  | "form" | "action-panel" | "action" | "navigation" | "spacer" | "text"
  | "image" | "code" | "progress" | "button" | "text-field" | "toggle" | "slider";

export interface UiNode {
  kind: UiNodeKind;
  id: string;
  children?: UiNode[];
  [key: string]: unknown;
}

export type UiPatch =
  | { kind: "replace-root"; node: UiNode }
  | { kind: "replace-node"; id: string; node: UiNode }
  | { kind: "append-children"; id: string; children: UiNode[] }
  | { kind: "set-text"; id: string; value: string }
  | { kind: "set-value"; id: string; value: unknown }
  | { kind: "remove"; id: string };

export type UiEvent =
  | { kind: "button-click"; action: string }
  | { kind: "action-invoked"; id: string; action: string }
  | { kind: "text-changed"; id: string; value: string }
  | { kind: "toggle-changed"; id: string; value: boolean }
  | { kind: "slider-changed"; id: string; value: number };

export interface UiSink {
  open(root: UiNode): void;
  patch(patches: UiPatch[]): void;
  close(): void;
  error?(error: Error): void;
}

export interface AtlasRoot {
  render(element: ReactElement): void;
  dispatch(event: UiEvent): void;
  snapshot(): UiNode | undefined;
  unmount(): void;
}
