import type { ReactTestRendererJSON } from "react-test-renderer";
import type { UiNode } from "./types.js";

const containers = new Set(["vstack", "hstack", "section", "list", "form", "action-panel", "navigation"]);
const ignoredProps = new Set(["children", "onAction", "onChange", "onSubmit"]);

function textValue(children: Array<ReactTestRendererJSON | string> | null): string {
  return (children ?? []).filter((child): child is string => typeof child === "string").join("");
}

export function jsonToUiNode(json: ReactTestRendererJSON, path = "root"): UiNode {
  const props = json.props as Record<string, unknown>;
  const kind = json.type.replace(/^atlas-/, "") as UiNode["kind"];
  const id = typeof props.id === "string" && props.id.length > 0 ? props.id : path;
  const node: UiNode = { kind, id };

  for (const [key, value] of Object.entries(props)) {
    if (!ignoredProps.has(key) && value !== undefined) node[key] = value;
  }

  const childJson = (json.children ?? []).filter(
    (child): child is ReactTestRendererJSON => typeof child !== "string",
  );
  if (containers.has(kind)) {
    node.children = childJson.map((child, index) => jsonToUiNode(child, `${id}.${index}`));
  }
  if (kind === "text") node.value = typeof props.value === "string" ? props.value : textValue(json.children);
  if (kind === "code") node.value = typeof props.value === "string" ? props.value : textValue(json.children);
  if (kind === "button") node.action = typeof props.action === "string" ? props.action : id;
  if (kind === "action") node.action = typeof props.action === "string" ? props.action : id;
  return node;
}
