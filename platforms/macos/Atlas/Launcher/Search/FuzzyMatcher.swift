import Foundation

/// 子序列模糊匹配,算法移植自 fzf 的 FuzzyMatchV1
/// (https://github.com/junegunn/fzf, MIT License, © Junegunn Choi):
/// 前向找首个可行匹配区间,再回溯收紧起点,按 fzf 计分表打分并回传命中位置。
enum FuzzyMatcher {
    struct Result: Equatable {
        let score: Int
        /// 命中字符在候选串(UTF-16 offset)上的位置,升序。
        let positions: [Int]
    }

    // fzf 计分表。
    private static let scoreMatch = 16
    private static let scoreGapStart = -3
    private static let scoreGapExtension = -1
    private static let bonusBoundary = 8
    private static let bonusNonWord = 8
    private static let bonusCamel123 = 7
    private static let bonusConsecutive = -(scoreGapStart + scoreGapExtension)
    private static let bonusFirstCharMultiplier = 2

    private enum CharClass {
        case lower, upper, digit, nonWord
    }

    private static func charClass(_ scalar: Character) -> CharClass {
        if scalar.isLowercase { return .lower }
        if scalar.isUppercase { return .upper }
        if scalar.isNumber { return .digit }
        if scalar.isLetter { return .lower } // 中文等字母类字符按 word 处理
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

    /// 全子序列命中返回分数+位置;任一查询字符未命中返回 nil。大小写不敏感。
    static func match(query: String, candidate: String) -> Result? {
        guard !query.isEmpty else { return nil }
        let pattern = Array(query.lowercased())
        let chars = Array(candidate)
        let lowered = Array(candidate.lowercased())
        guard pattern.count <= lowered.count else { return nil }

        // 前向:找到最小结束位置。
        var pidx = 0
        var start = -1
        var end = -1
        for index in 0..<lowered.count {
            if lowered[index] == pattern[pidx] {
                if start < 0 { start = index }
                pidx += 1
                if pidx == pattern.count {
                    end = index
                    break
                }
            }
        }
        guard end >= 0 else { return nil }

        // 回溯:从 end 往回收紧起点。
        pidx = pattern.count - 1
        var sidx = end
        var backtrackStart = end
        while sidx >= start {
            if lowered[sidx] == pattern[pidx] {
                backtrackStart = sidx
                if pidx == 0 { break }
                pidx -= 1
            }
            sidx -= 1
        }

        // 计分 + 收集位置(贪心:区间内按序匹配)。
        var score = 0
        var positions: [Int] = []
        var inGap = false
        var consecutive = 0
        var firstBonus = 0
        var qi = 0
        var prevClass: CharClass = backtrackStart > 0 ? charClass(chars[backtrackStart - 1]) : .nonWord

        for index in backtrackStart...end {
            let currentClass = charClass(chars[index])
            if qi < pattern.count, lowered[index] == pattern[qi] {
                positions.append(index)
                score += scoreMatch
                var currentBonus = bonus(prev: prevClass, current: currentClass)
                if consecutive == 0 {
                    firstBonus = currentBonus
                } else {
                    // 连续段沿用段首 boundary 加成(fzf 语义)。
                    if currentBonus == bonusBoundary {
                        firstBonus = currentBonus
                    }
                    currentBonus = max(currentBonus, max(firstBonus, bonusConsecutive))
                }
                score += (index == positions.first && index == 0)
                    ? currentBonus * bonusFirstCharMultiplier
                    : currentBonus
                inGap = false
                consecutive += 1
                qi += 1
            } else {
                score += inGap ? scoreGapExtension : scoreGapStart
                inGap = true
                consecutive = 0
                firstBonus = 0
            }
            prevClass = currentClass
        }
        guard qi == pattern.count else { return nil }
        return Result(score: score, positions: positions)
    }
}
