import React from "react";
export const Detail = (props: { id?: string; markdown?: string; metadata?: Array<[string, string]>; isLoading?: boolean }) =>
  <atlas-detail {...props} markdown={props.markdown ?? ""} />;
declare module "react" { namespace JSX { interface IntrinsicElements { "atlas-detail": Record<string, unknown> }}}
