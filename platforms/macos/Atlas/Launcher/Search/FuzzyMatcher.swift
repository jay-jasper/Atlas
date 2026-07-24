import Foundation

/// fzf-style fuzzy matcher.
///
/// The scorer follows fzf's V2 shape: dynamic programming chooses the globally
/// best alignment while boundary, camelCase and consecutive matches receive
/// bonuses and gaps receive penalties. The implementation is intentionally
/// self-contained so launcher search never shells out to `fzf`.
enum FuzzyMatcher {
    struct Result: Equatable, Sendable {
        let score: Int
        /// Matched Character offsets in the candidate, ascending.
        let positions: [Int]
    }

    struct Pattern: Sendable {
        let raw: String
        let characters: [String]
        let caseSensitive: Bool

        init(_ raw: String) {
            self.raw = raw
            let usesCaseSensitiveMatching = raw.contains { $0.isUppercase }
            caseSensitive = usesCaseSensitiveMatching
            characters = raw.map {
                usesCaseSensitiveMatching ? String($0) : String($0).lowercased()
            }
        }
    }

    struct PreparedCandidate: Sendable {
        fileprivate let characters: [Character]
        fileprivate let comparable: [String]
        fileprivate let bonuses: [Int]

        init(_ text: String) {
            characters = Array(text)
            comparable = characters.map { String($0).lowercased() }

            var computed: [Int] = []
            computed.reserveCapacity(characters.count)
            var previous: CharClass = .nonWord
            for character in characters {
                let current = FuzzyMatcher.charClass(character)
                computed.append(FuzzyMatcher.bonus(prev: previous, current: current))
                previous = current
            }
            bonuses = computed
        }
    }

    // fzf score constants.
    private static let scoreMatch = 16
    private static let scoreGapStart = -3
    private static let scoreGapExtension = -1
    private static let bonusBoundary = 8
    private static let bonusNonWord = 8
    private static let bonusCamel123 = 7
    private static let bonusConsecutive = -(scoreGapStart + scoreGapExtension)
    private static let bonusFirstCharMultiplier = 2
    private static let impossible = Int.min / 4

    private enum CharClass {
        case lower, upper, digit, nonWord
    }

    private static func charClass(_ scalar: Character) -> CharClass {
        if scalar.isLowercase { return .lower }
        if scalar.isUppercase { return .upper }
        if scalar.isNumber { return .digit }
        if scalar.isLetter { return .lower }
        return .nonWord
    }

    private static func bonus(prev: CharClass, current: CharClass) -> Int {
        if prev == .nonWord && current != .nonWord {
            return bonusBoundary
        }
        if (prev == .lower && current == .upper)
            || (current == .digit && prev != .digit) {
            return bonusCamel123
        }
        if current == .nonWord {
            return bonusNonWord
        }
        return 0
    }

    /// Smart-case fuzzy match. Lowercase patterns ignore case; a pattern with
    /// any uppercase character becomes case-sensitive.
    static func match(query: String, candidate: String) -> Result? {
        match(pattern: Pattern(query), candidate: PreparedCandidate(candidate))
    }

    static func match(pattern: Pattern, candidate: PreparedCandidate) -> Result? {
        let needle = pattern.characters
        let count = candidate.characters.count
        guard !needle.isEmpty, needle.count <= count else { return nil }

        let haystack = pattern.caseSensitive
            ? candidate.characters.map(String.init)
            : candidate.comparable

        var previous = Array(repeating: impossible, count: count)
        var previousFirstBonus = Array(repeating: 0, count: count)
        var parents = Array(
            repeating: Array(repeating: -1, count: count),
            count: needle.count
        )

        for index in 0..<count where haystack[index] == needle[0] {
            let leadingGap = index == 0
                ? 0
                : scoreGapStart + (index - 1) * scoreGapExtension
            let multiplier = index == 0 ? bonusFirstCharMultiplier : 1
            previous[index] = scoreMatch
                + candidate.bonuses[index] * multiplier
                + leadingGap
            previousFirstBonus[index] = candidate.bonuses[index]
        }

        if needle.count > 1 {
            for patternIndex in 1..<needle.count {
                var current = Array(repeating: impossible, count: count)
                var currentFirstBonus = Array(repeating: 0, count: count)
                var bestGapBase = impossible
                var bestGapParent = -1

                for index in 0..<count {
                    let gapCandidate = index - 2
                    if gapCandidate >= 0, previous[gapCandidate] > impossible {
                        let base = previous[gapCandidate] - scoreGapExtension * gapCandidate
                        if base > bestGapBase {
                            bestGapBase = base
                            bestGapParent = gapCandidate
                        }
                    }

                    guard haystack[index] == needle[patternIndex] else { continue }

                    var bestScore = impossible
                    var bestParent = -1
                    var firstBonus = candidate.bonuses[index]

                    if index > 0, previous[index - 1] > impossible {
                        let inherited = previousFirstBonus[index - 1]
                        let consecutiveBonus = max(
                            candidate.bonuses[index],
                            max(inherited, bonusConsecutive)
                        )
                        bestScore = previous[index - 1] + scoreMatch + consecutiveBonus
                        bestParent = index - 1
                        firstBonus = candidate.bonuses[index] == bonusBoundary
                            ? candidate.bonuses[index]
                            : inherited
                    }

                    if bestGapParent >= 0 {
                        let gapScore = bestGapBase
                            + scoreGapStart
                            + scoreGapExtension * (index - 1)
                            + scoreMatch
                            + candidate.bonuses[index]
                        if gapScore > bestScore {
                            bestScore = gapScore
                            bestParent = bestGapParent
                            firstBonus = candidate.bonuses[index]
                        }
                    }

                    current[index] = bestScore
                    currentFirstBonus[index] = firstBonus
                    parents[patternIndex][index] = bestParent
                }

                previous = current
                previousFirstBonus = currentFirstBonus
            }
        }

        var end = -1
        var score = impossible
        for index in 0..<count where previous[index] > score {
            score = previous[index]
            end = index
        }
        guard end >= 0, score > impossible else { return nil }

        var positions = Array(repeating: 0, count: needle.count)
        var position = end
        for patternIndex in stride(from: needle.count - 1, through: 0, by: -1) {
            positions[patternIndex] = position
            if patternIndex > 0 {
                position = parents[patternIndex][position]
                guard position >= 0 else { return nil }
            }
        }
        return Result(score: score, positions: positions)
    }
}
