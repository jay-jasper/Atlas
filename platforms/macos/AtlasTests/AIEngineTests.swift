import XCTest
@testable import Atlas

@MainActor
final class AIEngineTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "AIEngineTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testEngineCodecRoundTrip() throws {
        let engines: [AiEngine] = [
            .cli(id: "claude-code", path: "/usr/local/bin/claude", model: "sonnet"),
            .cli(id: "codex", path: "/opt/homebrew/bin/codex", model: nil),
            .byok(providerID: "byok-openai"),
        ]
        for engine in engines {
            let data = try JSONEncoder().encode(engine)
            XCTAssertEqual(try JSONDecoder().decode(AiEngine.self, from: data), engine)
        }
    }

    func testEngineStorePersists() {
        let store = AIEngineStore(defaults: defaults)
        store.engine = .cli(id: "claude-code", path: "/x/claude", model: "opus")
        XCTAssertEqual(
            AIEngineStore(defaults: defaults).engine,
            .cli(id: "claude-code", path: "/x/claude", model: "opus")
        )
    }

    func testEngineLabel() {
        XCTAssertEqual(AiEngine.cli(id: "claude-code", path: "/x", model: "sonnet").label, "Claude Code · sonnet")
        XCTAssertEqual(AiEngine.cli(id: "codex", path: "/x", model: nil).label, "Codex CLI")
        XCTAssertEqual(AiEngine.byok(providerID: "p").label, "BYOK")
    }

    func testByokPresetsCompleteAndMapped() {
        XCTAssertEqual(ByokPreset.all.count, 40)
        XCTAssertEqual(ByokPreset.all.first?.baseURL, "https://api.openai.com/v1")
        // 自定义 preset 必须存在且字段为空模板。
        let custom = ByokPreset.all.last
        XCTAssertEqual(custom?.id, "custom")
        XCTAssertEqual(custom?.baseURL, "")
        // id 唯一;本地引擎(Ollama/vLLM)不要求 key。
        XCTAssertEqual(Set(ByokPreset.all.map(\.id)).count, ByokPreset.all.count)
        XCTAssertFalse(ByokPreset.all.first { $0.id == "ollama" }!.requiresKey)
        // 带图标的预设,图标资源必须真实存在。
        for preset in ByokPreset.all {
            if let icon = preset.icon {
                XCTAssertNotNil(
                    Bundle(for: AIEngineTests.self).url(forResource: "ProviderIcon-\(icon)", withExtension: "svg")
                        ?? Bundle.main.url(forResource: "ProviderIcon-\(icon)", withExtension: "svg"),
                    "missing icon for \(preset.id)"
                )
            }
        }
    }
}
