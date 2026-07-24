import React from "react";

export interface WebViewProps {
  id?: string;
  url: string;
  allowedHosts: readonly string[];
  profile?: string;
  persistent?: boolean;
}

export function WebView({
  id = "web-view",
  url,
  allowedHosts,
  profile = "default",
  persistent = true,
}: WebViewProps) {
  return (
    <atlas-web-view
      id={id}
      url={url}
      allowed_hosts={[...allowedHosts]}
      profile={profile}
      persistent={persistent}
    />
  );
}

declare module "react" {
  namespace JSX {
    interface IntrinsicElements {
      "atlas-web-view": Record<string, unknown>;
    }
  }
}
