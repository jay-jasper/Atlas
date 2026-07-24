import XCTest
@testable import Atlas

@MainActor
final class AppLauncherProviderTests: XCTestCase {
    func testEmptyQueryReturnsNoResults() {
        let provider = AppLauncherProvider(apps: fakeApps())
        XCTAssertEqual(provider.results(for: "").count, 0)
    }

    func testExactPrefixMatchScoresHighest() {
        let apps = [
            AppEntry(name: "Safari", url: url("Safari")),
            AppEntry(name: "Xcode", url: url("Xcode")),
            AppEntry(name: "Slack", url: url("Slack")),
        ]
        let provider = AppLauncherProvider(apps: apps)
        let results = provider.results(for: "Saf")
        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.title, "Safari")
    }

    func testResultsAreCappedAtFive() {
        let apps = (1...10).map { i in
            AppEntry(name: "App\(i)", url: url("App\(i)"))
        }
        let provider = AppLauncherProvider(apps: apps)
        let results = provider.results(for: "app")
        XCTAssertLessThanOrEqual(results.count, 5)
    }

    func testCaseInsensitiveMatching() {
        let apps = [AppEntry(name: "TextEdit", url: url("TextEdit"))]
        let provider = AppLauncherProvider(apps: apps)
        XCTAssertFalse(provider.results(for: "textedit").isEmpty)
        XCTAssertFalse(provider.results(for: "TEXTEDIT").isEmpty)
        XCTAssertFalse(provider.results(for: "TextEdit").isEmpty)
    }

    func testNonMatchingQueryReturnsEmpty() {
        let provider = AppLauncherProvider(apps: fakeApps())
        XCTAssertTrue(provider.results(for: "xyzzy9999").isEmpty)
    }

    func testAllResultsHaveAppCategory() {
        let apps = [AppEntry(name: "Safari", url: url("Safari"))]
        let provider = AppLauncherProvider(apps: apps)
        let results = provider.results(for: "safari")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.category == "App" })
    }

    func testFuzzyMatchFindsNonPrefixMatch() {
        let apps = [AppEntry(name: "System Preferences", url: url("System Preferences"))]
        let provider = AppLauncherProvider(apps: apps)
        
        let results = provider.results(for: "prefs")
        XCTAssertFalse(results.isEmpty, "Fuzzy scorer failed to find System Preferences using query 'prefs'")
        XCTAssertEqual(results.first?.title, "System Preferences")
        XCTAssertEqual(results.first?.category, "App")
    }

    func testFuzzyMatchDoesNotJumpAcrossUnrelatedWords() {
        let provider = AppLauncherProvider(apps: [
            AppEntry(name: "System Settings", url: url("System Settings")),
        ])

        XCTAssertTrue(provider.results(for: "test").isEmpty)
        XCTAssertEqual(provider.results(for: "ss").first?.title, "System Settings")
    }

    func testSparseFuzzyMatchIsRejected() {
        let provider = AppLauncherProvider(apps: [
            AppEntry(name: "TablePlus", url: url("TablePlus")),
        ])

        XCTAssertTrue(provider.results(for: "tes").isEmpty)
        XCTAssertEqual(provider.results(for: "tplus").first?.title, "TablePlus")
    }

    // MARK: - Fuzzy score tests

    func testFuzzyScoreReturnsHigherScoreForConsecutiveMatch() {
        let consecutiveScore = AppLauncherProvider.fuzzyScore(query: "saf", in: "Safari")
        let nonConsecutiveScore = AppLauncherProvider.fuzzyScore(query: "sri", in: "Safari")
        XCTAssertGreaterThan(consecutiveScore, nonConsecutiveScore)
    }

    func testFuzzyScoreReturnsZeroForNoMatch() {
        let score = AppLauncherProvider.fuzzyScore(query: "xyz", in: "Safari")
        XCTAssertEqual(score, 0)
    }

    // MARK: - Helpers

    private func fakeApps() -> [AppEntry] {
        [
            AppEntry(name: "Safari", url: url("Safari")),
            AppEntry(name: "Xcode", url: url("Xcode")),
        ]
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/Applications/\(name).app")
    }
}


extension AppLauncherProviderTests {
    func testLocalizedNameSearchable() {
        let provider = AppLauncherProvider(apps: [
            AppEntry(name: "WeChat", url: URL(fileURLWithPath: "/Applications/WeChat.app"), localizedName: "微信"),
        ])

        // 中文本地化名直搜。
        XCTAssertEqual(provider.results(for: "微信").first?.title, "微信")
        // 英文原名仍可搜(进 keywords)。
        XCTAssertEqual(provider.results(for: "wechat").first?.title, "微信")
    }

    func testSystemSettingsPaneSearchableInChinese() {
        var opened: String?
        let provider = SystemSettingsProvider(openTarget: { opened = $0 })

        let byZh = provider.results(for: "蓝牙")
        XCTAssertEqual(byZh.count, 1)
        let byEn = provider.results(for: "bluetooth")
        XCTAssertEqual(byEn.count, 1)

        if case .execute(let run) = byZh[0].action { run() }
        XCTAssertEqual(opened, "com.apple.BluetoothSettings")
    }

    func testSystemSettingsRootCommandDoesNotMatchEveryPaneByCategory() {
        var opened: String?
        let provider = SystemSettingsProvider(openTarget: { opened = $0 })

        let byZh = provider.results(for: "系统")
        XCTAssertEqual(byZh.count, 1)
        XCTAssertTrue(["系统设置", "System Settings"].contains(byZh[0].title))

        let byEn = provider.results(for: "system settings")
        XCTAssertEqual(byEn.count, 1)

        if case .execute(let run) = byZh[0].action { run() }
        XCTAssertEqual(opened, "")
    }
}
