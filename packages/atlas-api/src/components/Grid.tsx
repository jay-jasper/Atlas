import React, { type ReactNode } from "react";
export interface GridProps { id?: string; children?: ReactNode; columns?: number; searchBarPlaceholder?: string }
const Item = (props: { id: string; title: string; subtitle?: string; content?: string; actions?: ReactNode }) =>
  <atlas-list-item id={props.id} title={props.title} subtitle={props.subtitle} action={props.id}>{props.actions}</atlas-list-item>;
const Section = (props: { id?: string; title?: string; children?: ReactNode }) => <atlas-section {...props} />;
export const Grid = Object.assign((props: GridProps) => <atlas-list {...props} />, { Item, Section });
