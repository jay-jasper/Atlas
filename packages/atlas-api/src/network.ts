import { host } from "./host.js";
export interface AtlasRequestInit { method?: string; headers?: Record<string, string>; body?: string; signal?: AbortSignal }
export interface AtlasResponse { status: number; headers: Record<string, string>; body: string; json<T>(): Promise<T>; text(): Promise<string> }
export async function atlasFetch(input: string, init: AtlasRequestInit = {}): Promise<AtlasResponse> {
  const raw = await host.request<Omit<AtlasResponse, "json" | "text">>("network.https", { input, init: { ...init, signal: undefined } }, init.signal);
  return { ...raw, json: async <T>() => JSON.parse(raw.body) as T, text: async () => raw.body };
}
