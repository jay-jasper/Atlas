import { host } from "./host.js";
export type ToastOptions = { style?: "success" | "failure" | "animated"; title: string; message?: string };
export const showToast = (options: ToastOptions | string) => host.request("ui.toast", typeof options === "string" ? { title: options } : options);
export const showHUD = (title: string) => host.request<void>("ui.hud", { title });
export const confirmAlert = (options: { title: string; message?: string; primaryAction?: unknown; dismissAction?: unknown }) =>
  host.request<boolean>("ui.alert", options);
