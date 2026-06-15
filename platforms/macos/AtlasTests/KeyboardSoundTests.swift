import XCTest
@testable import Atlas

@MainActor
final class KeyboardSoundSelectorTests: XCTestCase {
    func testVariantIsStablePerKey() {
        let a = KeyboardSoundSelector.sound(for: 5, pack: .mechanical)
        let b = KeyboardSoundSelector.sound(for: 5, pack: .mechanical)
        XCTAssertEqual(a, b)
    }

    func testAccentKeysUseAccentSound() {
        XCTAssertEqual(KeyboardSoundSelector.sound(for: 36, pack: .typewriter), KeyboardSoundPack.typewriter.accentSound)
        XCTAssertEqual(KeyboardSoundSelector.sound(for: 49, pack: .soft), KeyboardSoundPack.soft.accentSound)
    }

    func testVariantIndexInBounds() {
        for keyCode in 0..<60 {
            let index = KeyboardSoundSelector.variantIndex(keyCode: keyCode, variantCount: 3)
            XCTAssertTrue((0..<3).contains(index))
        }
    }

    func testEveryPackHasVariants() {
        for pack in KeyboardSoundPack.allCases {
            XCTAssertFalse(pack.variants.isEmpty)
        }
    }
}

private final class SpyPlayer: SoundPlaying {
    private(set) var played: [String] = []
    func play(named name: String) { played.append(name) }
}

@MainActor
final class KeyboardSoundServiceTests: XCTestCase {
    func testPlayKeyUsesPack() {
        let spy = SpyPlayer()
        let service = KeyboardSoundService(player: spy)
        service.pack = .mechanical
        service.playKey(keyCode: 1)
        XCTAssertEqual(spy.played.count, 1)
        XCTAssertEqual(spy.played.first, KeyboardSoundSelector.sound(for: 1, pack: .mechanical))
    }
}
