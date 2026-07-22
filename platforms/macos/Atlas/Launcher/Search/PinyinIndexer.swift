import Foundation

/// 汉字→拼音索引(CFStringTransform,系统能力零依赖)。
/// 每条文本缓存:全拼(音节数组,对应原字符位置)与首字母串。
enum PinyinIndexer {
    struct Index {
        /// 每个原字符对应一个音节(非中文字符 = 自身小写)。
        let syllables: [String]
        /// 全拼连接串(小写,无分隔)。
        let full: String
        /// 每个音节在 full 中的起始 offset。
        let syllableOffsets: [Int]
        /// 首字母串。
        let initials: String
        /// 是否含中文(不含则拼音索引无意义)。
        let hasChinese: Bool
    }

    private static let cache = NSCache<NSString, Wrapper>()
    private final class Wrapper {
        let index: Index
        init(_ index: Index) { self.index = index }
    }

    static func index(_ text: String) -> Index {
        if let cached = cache.object(forKey: text as NSString) {
            return cached.index
        }

        var syllables: [String] = []
        var hasChinese = false
        for character in text {
            if character.unicodeScalars.contains(where: { $0.value >= 0x4E00 && $0.value <= 0x9FFF }) {
                hasChinese = true
                let mutable = NSMutableString(string: String(character))
                CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
                CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
                syllables.append((mutable as String).lowercased().replacingOccurrences(of: " ", with: ""))
            } else {
                syllables.append(String(character).lowercased())
            }
        }

        var full = ""
        var offsets: [Int] = []
        var initials = ""
        for syllable in syllables {
            offsets.append(full.utf16.count)
            full += syllable
            initials += syllable.prefix(1)
        }

        let index = Index(
            syllables: syllables,
            full: full,
            syllableOffsets: offsets,
            initials: initials,
            hasChinese: hasChinese
        )
        cache.setObject(Wrapper(index), forKey: text as NSString)
        return index
    }

    /// 综合匹配:原文 → 全拼(×0.9)→ 首字母(×0.85),返回最高分与
    /// 映射回**原文**字符位置的高亮。
    static func bestMatch(query: String, text: String) -> (score: Int, positions: [Int])? {
        var best: (score: Int, positions: [Int])?

        if let direct = FuzzyMatcher.match(query: query, candidate: text) {
            best = (direct.score, direct.positions)
        }

        let idx = index(text)
        guard idx.hasChinese else { return best }

        if let fullMatch = FuzzyMatcher.match(query: query, candidate: idx.full) {
            let score = Int(Double(fullMatch.score) * 0.9)
            if best == nil || score > best!.score {
                let chars = mapFullOffsetsToChars(fullMatch.positions, index: idx)
                best = (score, chars)
            }
        }

        if let initialMatch = FuzzyMatcher.match(query: query, candidate: idx.initials) {
            let score = Int(Double(initialMatch.score) * 0.85)
            if best == nil || score > best!.score {
                // initials 每个位置即原字符序号。
                best = (score, initialMatch.positions)
            }
        }

        return best
    }

    /// full-pinyin 命中 offset → 原字符序号(去重保序)。
    private static func mapFullOffsetsToChars(_ offsets: [Int], index: Index) -> [Int] {
        var result: [Int] = []
        for offset in offsets {
            // 找到最后一个 syllableOffset <= offset 的音节。
            var low = 0, high = index.syllableOffsets.count - 1, found = 0
            while low <= high {
                let mid = (low + high) / 2
                if index.syllableOffsets[mid] <= offset {
                    found = mid
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            if result.last != found {
                result.append(found)
            }
        }
        return result
    }
}
