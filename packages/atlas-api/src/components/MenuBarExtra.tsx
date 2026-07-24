import React, { type ReactNode } from "react";
const Item = (props: { id?: string; title: string; onAction?(): void; shortcut?: unknown }) => <atlas-action id={props.id} title={props.title} action={props.id ?? props.title} onAction={props.onAction} />;
const Section = (props: { id?: string; title?: string; children?: ReactNode }) => <atlas-section {...props} />;
const Separator = () => <atlas-spacer />;
export const MenuBarExtra = Object.assign((props: { id?: string; title?: string; icon?: string; children?: ReactNode; isLoading?: boolean }) =>
  <atlas-navigation id={props.id} title={props.title ?? ""}>{props.children}</atlas-navigation>, { Item, Section, Separator });
declare module "react" { namespace JSX { interface IntrinsicElements { "atlas-navigation": Record<string, unknown> }}}
