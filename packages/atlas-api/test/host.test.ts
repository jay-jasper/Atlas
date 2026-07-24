import { describe, expect, it } from "vitest";
import { host, installHost, unloadHost, type HostRequest, type HostResponse, type HostTransport } from "../src/index.js";

class FakeTransport implements HostTransport {
  listener?: (response: HostResponse) => void;
  request?: HostRequest;
  send(request: HostRequest) { this.request = request; }
  subscribe(listener: (response: HostResponse) => void) { this.listener = listener; return () => { this.listener = undefined; }; }
}
describe("host RPC", () => {
  it("correlates responses and maps permission errors", async () => {
    const transport = new FakeTransport();
    installHost(transport);
    const pending = host.request("clipboard.read", {});
    transport.listener?.({ protocolVersion: 1, requestId: transport.request!.requestId, error: { code: "permission-denied" } });
    await expect(pending).rejects.toMatchObject({ code: "permission-denied" });
    unloadHost();
  });
});
