import React, { type ReactNode } from "react";
import type { KeyboardShortcut } from "./primitives.js";
export const Action = (props: {
  id?: string;
  title: string;
  onAction?(): void;
  shortcut?: KeyboardShortcut;
  icon?: string;
  selected?: boolean;
}) => {
  const id = props.id ?? `action-${props.title.toLowerCase().replaceAll(/[^a-z0-9]+/g, "-")}`;
  return <atlas-action {...props} id={id} action={id} />;
};
const Section = (props: { id?: string; title?: string; children?: ReactNode }) => <atlas-section {...props} />;
export const ActionPanel = Object.assign((props: { id?: string; title?: string; children?: ReactNode }) => <atlas-action-panel {...props} />, { Section });
declare module "react" { namespace JSX { interface IntrinsicElements {
  "atlas-action": Record<string, unknown>; "atlas-action-panel": Record<string, unknown>;
}}}
