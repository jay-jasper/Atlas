import { AtlasApiError } from "./errors.js";

export const hostProtocolVersion = 1 as const;
export type HostProtocolVersion = typeof hostProtocolVersion;
export type CapabilityId = string;

export interface HostRequest {
  protocolVersion: HostProtocolVersion;
  requestId: string;
  capability: CapabilityId;
  payload: unknown;
}

export interface HostResponse {
  protocolVersion: HostProtocolVersion;
  requestId: string;
  result?: unknown;
  error?: { code: string; message?: string; recovery?: string };
}

export interface HostTransport {
  send(request: HostRequest): void;
  subscribe(listener: (response: HostResponse) => void): () => void;
}

export interface AtlasHost {
  request<T>(capability: CapabilityId, payload: unknown, signal?: AbortSignal): Promise<T>;
}

class TransportHost implements AtlasHost {
  private sequence = 0;
  private active = true;
  private readonly pending = new Map<string, {
    resolve(value: unknown): void;
    reject(error: Error): void;
  }>();
  private readonly completed = new Set<string>();
  private readonly unsubscribe: () => void;

  constructor(private readonly transport: HostTransport) {
    this.unsubscribe = transport.subscribe((response) => this.receive(response));
  }

  request<T>(capability: CapabilityId, payload: unknown, signal?: AbortSignal): Promise<T> {
    if (!this.active) return Promise.reject(new AtlasApiError("runtime-unloaded", "Plugin runtime is unloaded"));
    if (signal?.aborted) return Promise.reject(new AtlasApiError("aborted", "Host request was aborted"));
    const requestId = `atlas-${++this.sequence}`;
    return new Promise<T>((resolve, reject) => {
      const abort = () => {
        this.pending.delete(requestId);
        reject(new AtlasApiError("aborted", "Host request was aborted"));
      };
      signal?.addEventListener("abort", abort, { once: true });
      this.pending.set(requestId, {
        resolve: (value) => {
          signal?.removeEventListener("abort", abort);
          resolve(value as T);
        },
        reject: (error) => {
          signal?.removeEventListener("abort", abort);
          reject(error);
        },
      });
      this.transport.send({ protocolVersion: hostProtocolVersion, requestId, capability, payload });
    });
  }

  unload(): void {
    if (!this.active) return;
    this.active = false;
    this.unsubscribe();
    for (const pending of this.pending.values()) {
      pending.reject(new AtlasApiError("runtime-unloaded", "Plugin runtime is unloaded"));
    }
    this.pending.clear();
  }

  private receive(response: HostResponse): void {
    if (response.protocolVersion !== hostProtocolVersion) {
      this.fail(response.requestId, new AtlasApiError("protocol-mismatch", "Host protocol version mismatch"));
      return;
    }
    if (this.completed.has(response.requestId)) {
      throw new AtlasApiError("duplicate-response", `Duplicate response ${response.requestId}`);
    }
    const pending = this.pending.get(response.requestId);
    if (!pending) throw new AtlasApiError("unknown-response", `Unknown response ${response.requestId}`);
    this.pending.delete(response.requestId);
    this.completed.add(response.requestId);
    if (response.error) {
      pending.reject(new AtlasApiError(
        response.error.code,
        response.error.message ?? response.error.code,
        response.error.recovery,
      ));
    } else {
      pending.resolve(response.result);
    }
  }

  private fail(requestId: string, error: Error): void {
    const pending = this.pending.get(requestId);
    if (!pending) throw error;
    this.pending.delete(requestId);
    pending.reject(error);
  }
}

let installed: AtlasHost | undefined;
let transportHost: TransportHost | undefined;

export const host: AtlasHost = {
  request<T>(capability: CapabilityId, payload: unknown, signal?: AbortSignal): Promise<T> {
    if (!installed) return Promise.reject(new AtlasApiError("host-unavailable", "Atlas host is not installed"));
    return installed.request<T>(capability, payload, signal);
  },
};

export function installHost(value: AtlasHost | HostTransport): () => void {
  unloadHost();
  if ("send" in value) {
    transportHost = new TransportHost(value);
    installed = transportHost;
  } else {
    installed = value;
  }
  return unloadHost;
}

export function unloadHost(): void {
  transportHost?.unload();
  transportHost = undefined;
  installed = undefined;
}
