import type { ReactElement } from "react";
import { act, create, type ReactTestInstance, type ReactTestRenderer } from "react-test-renderer";
import { jsonToUiNode } from "./hostConfig.js";
import type { AtlasRoot, UiEvent, UiNode, UiPatch, UiSink } from "./types.js";

function equal(a: unknown, b: unknown): boolean {
  return JSON.stringify(a) === JSON.stringify(b);
}

function diff(previous: UiNode, next: UiNode): UiPatch[] {
  if (previous.id !== next.id || previous.kind !== next.kind) {
    return [{ kind: "replace-node", id: previous.id, node: next }];
  }
  if ((next.kind === "text" || next.kind === "code") && previous.value !== next.value) {
    return [{ kind: "set-text", id: next.id, value: String(next.value ?? "") }];
  }
  const previousProps = { ...previous, children: undefined };
  const nextProps = { ...next, children: undefined };
  if (!equal(previousProps, nextProps)) {
    return [{ kind: "replace-node", id: previous.id, node: next }];
  }

  const oldChildren = previous.children ?? [];
  const newChildren = next.children ?? [];
  const oldIds = oldChildren.map(({ id }) => id);
  const newIds = newChildren.map(({ id }) => id);
  if (!equal(oldIds.filter((id) => newIds.includes(id)), newIds.filter((id) => oldIds.includes(id)))) {
    return [{ kind: "replace-node", id: previous.id, node: next }];
  }
  const patches: UiPatch[] = [];
  for (const child of oldChildren) {
    if (!newIds.includes(child.id)) patches.push({ kind: "remove", id: child.id });
  }
  const oldById = new Map(oldChildren.map((child) => [child.id, child]));
  for (const child of newChildren) {
    const old = oldById.get(child.id);
    if (old) patches.push(...diff(old, child));
  }
  const appended = newChildren.filter(({ id }) => !oldById.has(id));
  if (appended.length > 0) patches.push({ kind: "append-children", id: next.id, children: appended });
  return patches;
}

function findHandler(root: ReactTestInstance, event: UiEvent): (() => void) | undefined {
  const action = event.kind === "button-click" ? event.action
    : event.kind === "action-invoked" ? event.action : event.id;
  const candidates = root.findAll((instance) => {
    const props = instance.props as Record<string, unknown>;
    return props.id === action || props.action === action;
  });
  const props = candidates[0]?.props as Record<string, unknown> | undefined;
  if (!props) return undefined;
  if (event.kind === "text-changed" || event.kind === "toggle-changed" || event.kind === "slider-changed") {
    const onChange = props.onChange;
    return typeof onChange === "function" ? () => (onChange as (value: unknown) => void)(event.value) : undefined;
  }
  const onAction = props.onAction ?? props.onSubmit;
  return typeof onAction === "function" ? () => (onAction as () => void)() : undefined;
}

export function createAtlasRoot(sink: UiSink): AtlasRoot {
  let renderer: ReactTestRenderer | undefined;
  let current: UiNode | undefined;
  let closed = false;

  return {
    render(element) {
      if (closed) throw new Error("Atlas root is unmounted");
      try {
        act(() => {
          if (renderer) renderer.update(element);
          else renderer = create(element);
        });
        const activeRenderer = renderer;
        if (!activeRenderer) throw new Error("React renderer failed to initialize");
        const json = activeRenderer.toJSON();
        if (!json || Array.isArray(json) || typeof json === "string") {
          throw new Error("Atlas plugins must render exactly one root node");
        }
        const next = jsonToUiNode(json);
        if (!current) sink.open(next);
        else {
          const patches = diff(current, next);
          if (patches.length > 0) sink.patch(patches);
        }
        current = next;
      } catch (cause) {
        const error = cause instanceof Error ? cause : new Error(String(cause));
        sink.error?.(error);
        throw error;
      }
    },
    dispatch(event) {
      if (!renderer) throw new Error("Cannot dispatch before render");
      const handler = findHandler(renderer.root, event);
      if (!handler) throw new Error(`No handler registered for ${JSON.stringify(event)}`);
      act(handler);
    },
    snapshot: () => current,
    unmount() {
      if (closed) return;
      if (renderer) act(() => renderer?.unmount());
      closed = true;
      current = undefined;
      sink.close();
    },
  };
}
