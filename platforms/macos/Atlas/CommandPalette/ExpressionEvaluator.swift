import Foundation

/// Evaluates a mathematical expression string into a numeric value.
///
/// The default `live` implementation is a self-contained recursive-descent
/// evaluator so the calculator works without the Rust FFI bridge wired in.
/// It mirrors the capability surface of `atlas-core::calculator` (evalexpr):
/// `+ - * / ^`, parentheses, unary minus, the constants `pi`/`e`, and the
/// functions `sqrt`, `abs`, `floor`, `ceil`, `round`, `ln`, `log`, `log2`,
/// `sin`, `cos`, `tan`. Swapping in `AtlasBridge.evaluateExpression` later is a
/// one-line change.
protocol ExpressionEvaluating {
    /// Returns the evaluated value, or `nil` for malformed input / division by
    /// zero / a non-finite result.
    func evaluate(_ expression: String) -> Double?
}

struct NativeExpressionEvaluator: ExpressionEvaluating {
    func evaluate(_ expression: String) -> Double? {
        var parser = Parser(expression)
        guard let value = parser.parse(), value.isFinite else { return nil }
        return value
    }

    // MARK: - Recursive-descent parser

    private struct Parser {
        private let tokens: [Token]
        private var index = 0

        init(_ input: String) {
            tokens = Lexer.tokenize(input)
        }

        mutating func parse() -> Double? {
            guard !tokens.isEmpty else { return nil }
            guard let value = parseExpression() else { return nil }
            guard index == tokens.count else { return nil } // trailing garbage
            return value
        }

        private func peek() -> Token? {
            index < tokens.count ? tokens[index] : nil
        }

        private mutating func advance() -> Token? {
            defer { index += 1 }
            return peek()
        }

        // expression := term (('+' | '-') term)*
        private mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while case .op(let c)? = peek(), c == "+" || c == "-" {
                index += 1
                guard let rhs = parseTerm() else { return nil }
                value = (c == "+") ? value + rhs : value - rhs
            }
            return value
        }

        // term := factor (('*' | '/') factor)*
        private mutating func parseTerm() -> Double? {
            guard var value = parseFactor() else { return nil }
            while case .op(let c)? = peek(), c == "*" || c == "/" {
                index += 1
                guard let rhs = parseFactor() else { return nil }
                if c == "/" {
                    guard rhs != 0 else { return nil }
                    value /= rhs
                } else {
                    value *= rhs
                }
            }
            return value
        }

        // factor := base ('^' factor)?   (right-associative)
        private mutating func parseFactor() -> Double? {
            guard let base = parseUnary() else { return nil }
            if case .op("^")? = peek() {
                index += 1
                guard let exponent = parseFactor() else { return nil }
                return pow(base, exponent)
            }
            return base
        }

        // unary := ('-' | '+') unary | primary
        private mutating func parseUnary() -> Double? {
            if case .op(let c)? = peek(), c == "-" || c == "+" {
                index += 1
                guard let value = parseUnary() else { return nil }
                return c == "-" ? -value : value
            }
            return parsePrimary()
        }

        // primary := number | constant | function '(' expression ')' | '(' expression ')'
        private mutating func parsePrimary() -> Double? {
            switch advance() {
            case .number(let n):
                return n
            case .identifier(let name):
                if let constant = Self.constants[name.lowercased()] {
                    return constant
                }
                // function call
                guard case .lparen? = peek() else { return nil }
                index += 1
                guard let arg = parseExpression() else { return nil }
                guard case .rparen? = peek() else { return nil }
                index += 1
                return Self.functions[name.lowercased()]?(arg)
            case .lparen:
                guard let value = parseExpression() else { return nil }
                guard case .rparen? = peek() else { return nil }
                index += 1
                return value
            default:
                return nil
            }
        }

        private static let constants: [String: Double] = [
            "pi": Double.pi,
            "e": M_E,
        ]

        private static let functions: [String: (Double) -> Double] = [
            "sqrt": { $0 < 0 ? .nan : sqrt($0) },
            "abs": abs,
            "floor": floor,
            "ceil": ceil,
            "round": { $0.rounded() },
            "ln": log,
            "log": log10,
            "log2": log2,
            "sin": sin,
            "cos": cos,
            "tan": tan,
        ]
    }

    private enum Token: Equatable {
        case number(Double)
        case identifier(String)
        case op(Character)
        case lparen
        case rparen
    }

    private enum Lexer {
        static func tokenize(_ input: String) -> [Token] {
            var tokens: [Token] = []
            let chars = Array(input)
            var i = 0
            while i < chars.count {
                let c = chars[i]
                if c.isWhitespace {
                    i += 1
                } else if c.isNumber || c == "." {
                    var num = ""
                    while i < chars.count, chars[i].isNumber || chars[i] == "." {
                        num.append(chars[i]); i += 1
                    }
                    guard let value = Double(num) else { return [] }
                    tokens.append(.number(value))
                } else if c.isLetter {
                    var name = ""
                    while i < chars.count, chars[i].isLetter || chars[i].isNumber {
                        name.append(chars[i]); i += 1
                    }
                    tokens.append(.identifier(name))
                } else if "+-*/^".contains(c) {
                    tokens.append(.op(c)); i += 1
                } else if c == "(" {
                    tokens.append(.lparen); i += 1
                } else if c == ")" {
                    tokens.append(.rparen); i += 1
                } else {
                    return [] // unknown character -> malformed
                }
            }
            return tokens
        }
    }
}
