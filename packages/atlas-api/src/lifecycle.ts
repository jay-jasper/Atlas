import { host } from "./host.js";
const subscriptions = new Set<() => void>();
export const setTimeout = (callback: () => void, milliseconds: number) => {
  let cancelled = false;
  void host.request<void>("timer.schedule", { milliseconds }).then(() => { if (!cancelled) callback(); });
  const cancel = () => { cancelled = true; };
  subscriptions.add(cancel);
  return cancel;
};
export const clearTimeout = (cancel: () => void) => { cancel(); subscriptions.delete(cancel); };
export const complete = (result?: unknown) => host.request<void>("command.complete", { result });
export const setMenuBarVisible = (visible: boolean) => host.request<void>("menu-bar.visibility", { visible });
export const cancelBackgroundWork = () => { subscriptions.forEach((cancel) => cancel()); subscriptions.clear(); };
