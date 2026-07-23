import Foundation

/// 片段自动展开匹配核心(纯逻辑,可测):环形缓冲最近击键,
/// 每键检查是否命中某关键词后缀。关键词需从"词首"起始
/// (缓冲开头,或前一字符是空白/标点分隔符),防止误触。
struct SnippetExpansionEngine {
    struct Match: Equatable {
        let snippetID: String
        let keyword: String
        let body: String
    }

    struct Entry: Equatable {
        let id: String
        let keyword: String
        let body: String
    }

    private(set) var buffer: String = ""
    private let capacity = 64
    private var entries: [Entry] = []

    init(entries: [Entry] = []) {
        self.entries = entries.filter { !$0.keyword.isEmpty }
    }

    mutating func updateEntries(_ entries: [Entry]) {
        self.entries = entries.filter { !$0.keyword.isEmpty }
    }

    /// 输入一个字符,返回命中(若有)。命中后缓冲清空。
    mutating func ingest(_ character: Character) -> Match? {
        if character == "\u{8}" { // backspace
            if !buffer.isEmpty { buffer.removeLast() }
            return nil
        }
        buffer.append(character)
        if buffer.count > capacity {
            buffer.removeFirst(buffer.count - capacity)
        }
        for entry in entries where buffer.hasSuffix(entry.keyword) {
            let prefixEnd = buffer.index(buffer.endIndex, offsetBy: -entry.keyword.count)
            let boundaryOK: Bool
            if prefixEnd == buffer.startIndex {
                boundaryOK = true
            } else {
                let before = buffer[buffer.index(before: prefixEnd)]
                boundaryOK = before.isWhitespace || before.isNewline || before.isPunctuation
            }
            if boundaryOK {
                buffer = ""
                return Match(snippetID: entry.id, keyword: entry.keyword, body: entry.body)
            }
        }
        return nil
    }

    /// 焦点切换/鼠标点击后调用:上下文变了,旧击键作废。
    mutating func reset() {
        buffer = ""
    }
}
