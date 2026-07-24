import React, { useState } from "react";
import { Action, HStack, Spacer, VStack, WebView } from "@atlas/api";

const providers = [
  {
    id: "chatgpt",
    name: "ChatGPT",
    icon: "sparkles",
    url: "https://chatgpt.com/",
    allowedHosts: ["chatgpt.com", "openai.com"],
  },
  {
    id: "grok",
    name: "Grok",
    icon: "bolt.fill",
    url: "https://grok.com/",
    allowedHosts: ["grok.com", "x.ai", "x.com", "twitter.com"],
  },
  {
    id: "gemini",
    name: "Gemini",
    icon: "diamond.fill",
    url: "https://gemini.google.com/app",
    allowedHosts: ["google.com"],
  },
] as const;

export type ProviderID = (typeof providers)[number]["id"];

export function AssistantHub({ initialProvider }: { initialProvider: ProviderID }) {
  const [selected, setSelected] = useState<ProviderID>(initialProvider);
  const provider = providers.find((candidate) => candidate.id === selected) ?? providers[0];

  return (
    <VStack id="ai-web-hub">
      <HStack id="provider-switcher">
        <Spacer id="switcher-leading-space" />
        {providers.map((candidate) => (
          <Action
            id={`select-${candidate.id}`}
            key={candidate.id}
            title={candidate.name}
            icon={candidate.icon}
            selected={candidate.id === selected}
            onAction={() => setSelected(candidate.id)}
          />
        ))}
        <Spacer id="switcher-trailing-space" />
      </HStack>
      <WebView
        id="assistant-browser"
        url={provider.url}
        allowedHosts={provider.allowedHosts}
        profile={provider.id}
        persistent
      />
    </VStack>
  );
}
