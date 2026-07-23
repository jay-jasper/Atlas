import Foundation

/// Dynamic Placeholders(Raycast 等价)纯解析器,全部可测。
/// 支持:{clipboard} {date} {date:格式} {time} {uuid} {cursor} {argument:提示}
enum SnippetPlaceholderParser {
    struct Resolved: Equatable {
        /// 最终插入文本({cursor} 已移除)。
        let text: String
        /// {cursor} 位置距文本末尾的字符数(nil = 无 cursor,粘贴后不回移)。
        let cursorOffsetFromEnd: Int?
        /// 按出现顺序的 {argument:提示} 提示语;由调用方弹窗取值后二次渲染。
        let argumentPrompts: [String]
    }

    /// 环境注入,测试可控。
    struct Context {
        var clipboard: () -> String
        var now: () -> Date
        var uuid: () -> String
        /// 参数值按 argumentPrompts 顺序;缺位补空串。
        var argumentValues: [String]

        static func live(argumentValues: [String] = []) -> Context {
            Context(
                clipboard: { NSPasteboardClipboardReader.read() },
                now: { Date() },
                uuid: { UUID().uuidString },
                argumentValues: argumentValues
            )
        }
    }

    /// 只扫参数提示,不做替换(第一遍,用于先弹窗)。
    static func argumentPrompts(in template: String) -> [String] {
        var prompts: [String] = []
        scan(template) { token in
            if case .argument(let prompt) = token {
                prompts.append(prompt)
            }
            return nil
        }
        return prompts
    }

    /// 完整渲染。
    static func resolve(_ template: String, context: Context) -> Resolved {
        var argumentIndex = 0
        var cursorMarkerIndexes: [Int] = []
        var output = ""

        scan(template) { token in
            switch token {
            case .literal(let ch):
                output.append(ch)
            case .clipboard:
                output.append(context.clipboard())
            case .date(let format):
                let formatter = DateFormatter()
                formatter.dateFormat = format ?? "yyyy-MM-dd"
                output.append(formatter.string(from: context.now()))
            case .time:
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                output.append(formatter.string(from: context.now()))
            case .uuid:
                output.append(context.uuid())
            case .cursor:
                cursorMarkerIndexes.append(output.count)
            case .argument:
                let value = argumentIndex < context.argumentValues.count
                    ? context.argumentValues[argumentIndex] : ""
                argumentIndex += 1
                output.append(value)
            }
            return nil
        }

        let cursorOffset: Int? = cursorMarkerIndexes.first.map { output.count - $0 }
        return Resolved(
            text: output,
            cursorOffsetFromEnd: cursorOffset,
            argumentPrompts: argumentPrompts(in: template)
        )
    }

    // MARK: - Tokenizer

    private enum Token {
        case literal(Character)
        case clipboard
        case date(String?)
        case time
        case uuid
        case cursor
        case argument(String)
    }

    /// 逐 token 回调;未知 `{xxx}` 原样当字面量。
    private static func scan(_ template: String, _ visit: (Token) -> Void?) {
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            for ch in rest[rest.startIndex..<open] {
                _ = visit(.literal(ch))
            }
            guard let close = rest[open...].firstIndex(of: "}") else {
                for ch in rest[open...] {
                    _ = visit(.literal(ch))
                }
                return
            }
            let inner = String(rest[rest.index(after: open)..<close])
            switch true {
            case inner == "clipboard":
                _ = visit(.clipboard)
            case inner == "date":
                _ = visit(.date(nil))
            case inner.hasPrefix("date:"):
                _ = visit(.date(String(inner.dropFirst(5))))
            case inner == "time":
                _ = visit(.time)
            case inner == "uuid":
                _ = visit(.uuid)
            case inner == "cursor":
                _ = visit(.cursor)
            case inner.hasPrefix("argument:"):
                _ = visit(.argument(String(inner.dropFirst(9))))
            case inner == "argument":
                _ = visit(.argument(""))
            default:
                for ch in rest[open...close] {
                    _ = visit(.literal(ch))
                }
            }
            rest = rest[rest.index(after: close)...]
        }
        for ch in rest {
            _ = visit(.literal(ch))
        }
    }
}

/// 剪贴板读取隔离,便于测试替身。
enum NSPasteboardClipboardReader {
    static func read() -> String {
        #if canImport(AppKit)
        return NSPasteboard.general.string(forType: .string) ?? ""
        #else
        return ""
        #endif
    }
}

#if canImport(AppKit)
import AppKit
#endif
