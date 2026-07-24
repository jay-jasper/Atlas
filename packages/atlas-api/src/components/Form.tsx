import React, { type ReactNode } from "react";
type FieldProps<T> = { id: string; title?: string; value?: T; defaultValue?: T; onChange?(value: T): void };
const TextField = (props: FieldProps<string> & { placeholder?: string }) => <atlas-text-field {...props} placeholder={props.placeholder ?? ""} />;
const TextArea = TextField;
const Checkbox = (props: FieldProps<boolean> & { label?: string }) => <atlas-toggle {...props} label={props.label ?? props.title ?? ""} value={props.value ?? props.defaultValue ?? false} />;
const Dropdown = (props: FieldProps<string> & { children?: ReactNode }) => <atlas-text-field {...props} placeholder={props.title ?? ""} />;
const DatePicker = (props: FieldProps<Date>) => <atlas-text-field {...props} value={props.value?.toISOString()} placeholder={props.title ?? ""} />;
const TagPicker = (props: FieldProps<string[]> & { children?: ReactNode }) => <atlas-text-field {...props} value={(props.value ?? []).join(",")} placeholder={props.title ?? ""} />;
const FilePicker = (props: FieldProps<string[]>) => <atlas-text-field {...props} value={(props.value ?? []).join(",")} placeholder={props.title ?? ""} />;
const Description = (props: { id?: string; text: string }) => <atlas-text {...props}>{props.text}</atlas-text>;
const Separator = (props: { id?: string }) => <atlas-spacer {...props} />;
export const Form = Object.assign((props: { id?: string; children?: ReactNode; actions?: ReactNode }) => <atlas-form {...props}>{props.children}{props.actions}</atlas-form>, {
  TextField, TextArea, Checkbox, Dropdown, DatePicker, TagPicker, FilePicker, Description, Separator,
});
declare module "react" { namespace JSX { interface IntrinsicElements {
  "atlas-form": Record<string, unknown>; "atlas-text-field": Record<string, unknown>; "atlas-toggle": Record<string, unknown>;
}}}
