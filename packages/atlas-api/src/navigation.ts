import type { ReactElement } from "react";
import { host } from "./host.js";

const stack: ReactElement[] = [];
export async function push(element: ReactElement): Promise<void> { stack.push(element); await host.request("ui.navigation", { operation: "push" }); }
export async function pop(): Promise<void> { stack.pop(); await host.request("ui.navigation", { operation: "pop" }); }
export async function popToRoot(): Promise<void> { stack.splice(1); await host.request("ui.navigation", { operation: "pop-to-root" }); }
export const closeMainWindow = (options?: { clearRootSearch?: boolean }) => host.request<void>("ui.window", { operation: "close", options });
export const launchCommand = (options: { name: string; type?: string; context?: unknown }) => host.request<void>("command.launch", options);
