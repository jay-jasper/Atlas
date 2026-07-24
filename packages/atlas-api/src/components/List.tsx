import React, { type ReactNode } from "react";

export interface ListProps {
  id?: string;
  children?: ReactNode;
  searchBarPlaceholder?: string;
  isLoading?: boolean;
  onSearchTextChange?(value: string): void;
}
export interface ListItemProps {
  id: string; title: string; subtitle?: string; keywords?: string[];
  accessories?: Array<{ text?: string; icon?: string }>; actions?: ReactNode;
}
const Item = ({ actions, ...props }: ListItemProps) => <atlas-list-item {...props} action={props.id}>{actions}</atlas-list-item>;
const Section = (props: { id?: string; title?: string; children?: ReactNode }) => <atlas-section {...props} />;
export const List = Object.assign((props: ListProps) => <atlas-list {...props} />, { Item, Section });

declare module "react" {
  namespace JSX { interface IntrinsicElements {
    "atlas-list": Record<string, unknown>; "atlas-list-item": Record<string, unknown>; "atlas-section": Record<string, unknown>;
  }}
}
