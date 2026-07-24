import { host } from "./host.js";
export const LocalStorage = {
  getItem: <T = string>(key: string) => host.request<T | undefined>("storage.read", { key }),
  setItem: (key: string, value: unknown) => host.request<void>("storage.write", { key, value }),
  removeItem: (key: string) => host.request<void>("storage.write", { key, remove: true }),
  allItems: () => host.request<Record<string, string>>("storage.read", { all: true }),
  clear: () => host.request<void>("storage.write", { clear: true }),
};
export class Cache {
  constructor(readonly namespace = "default", readonly capacity = 10 * 1024 * 1024) {}
  get<T = string>(key: string) { return host.request<T | undefined>("storage.cache.read", { namespace: this.namespace, key }); }
  set(key: string, value: unknown) { return host.request<void>("storage.cache.write", { namespace: this.namespace, key, value, capacity: this.capacity }); }
  remove(key: string) { return host.request<void>("storage.cache.write", { namespace: this.namespace, key, remove: true }); }
  clear() { return host.request<void>("storage.cache.write", { namespace: this.namespace, clear: true }); }
}
