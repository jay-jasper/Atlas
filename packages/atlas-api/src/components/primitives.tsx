import React, { type ReactNode } from "react";

type ChildrenProps = { id?: string; children?: ReactNode };
export const VStack = (props: ChildrenProps) => <vstack {...props} />;
export const HStack = (props: ChildrenProps) => <hstack {...props} />;
export const Text = ({ children, ...props }: ChildrenProps & { value?: string }) => <atlas-text {...props}>{children}</atlas-text>;
export const Image = (props: { id?: string; source: string }) => <atlas-image id={props.id} url={props.source} />;
export const Icon = Image;
export const Spacer = (props: { id?: string }) => <atlas-spacer {...props} />;
export const Progress = (props: { id?: string; value: number }) => <atlas-progress {...props} />;
export type Color = string;
export type KeyboardShortcut = { modifiers: string[]; key: string };

declare module "react" {
  namespace JSX {
    interface IntrinsicElements {
      vstack: Record<string, unknown>; hstack: Record<string, unknown>; "atlas-text": Record<string, unknown>;
      "atlas-image": Record<string, unknown>; "atlas-spacer": Record<string, unknown>; "atlas-progress": Record<string, unknown>;
    }
  }
}
