import { host } from "./host.js";
export type ClipboardContent = string | { text?: string; html?: string; file?: string };
export const Clipboard = {
  readText: () => host.request<string | undefined>("clipboard.read", {}),
  read: () => host.request<ClipboardContent | undefined>("clipboard.read", {}),
  copy: (content: ClipboardContent) => host.request<void>("clipboard.write", { content }),
  paste: (content: ClipboardContent) => host.request<void>("clipboard.write", { content, paste: true }),
  clear: () => host.request<void>("clipboard.write", { clear: true }),
};
