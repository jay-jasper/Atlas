import Foundation

struct EnvVariable: Equatable, Identifiable {
    var id: String { key }
    var key: String
    var value: String
}

/// Parses and serializes a managed block of `export KEY=VALUE` lines within a
/// shell rc file. Atlas only ever rewrites the region between its markers so the
/// rest of the user's rc file is preserved. Pure value logic — fully testable.
enum EnvDocument {
    static let beginMarker = "# >>> atlas env >>>"
    static let endMarker = "# <<< atlas env <<<"

    /// Extracts the variables Atlas manages from a full rc file.
    static func parseManaged(_ rcContents: String) -> [EnvVariable] {
        guard let block = managedBlock(rcContents) else { return [] }
        return parseExports(block)
    }

    /// Parses `export KEY=VALUE` / `export KEY="value"` lines.
    static func parseExports(_ text: String) -> [EnvVariable] {
        var result: [EnvVariable] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("export ") else { continue }
            let assignment = line.dropFirst("export ".count)
            guard let eq = assignment.firstIndex(of: "=") else { continue }
            let key = String(assignment[assignment.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(assignment[assignment.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            value = unquote(value)
            guard !key.isEmpty else { continue }
            result.append(EnvVariable(key: key, value: value))
        }
        return result
    }

    /// Returns a new rc file with Atlas's managed block replaced/inserted.
    static func applyManaged(_ variables: [EnvVariable], to rcContents: String) -> String {
        let block = serializeBlock(variables)
        if managedBlock(rcContents) != nil {
            return replaceBlock(in: rcContents, with: block)
        }
        let trimmed = rcContents.hasSuffix("\n") || rcContents.isEmpty ? rcContents : rcContents + "\n"
        return trimmed + block
    }

    static func serializeBlock(_ variables: [EnvVariable]) -> String {
        var lines = [beginMarker]
        for variable in variables {
            lines.append("export \(variable.key)=\(quote(variable.value))")
        }
        lines.append(endMarker)
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Helpers

    static func managedBlock(_ rcContents: String) -> String? {
        guard let beginRange = rcContents.range(of: beginMarker),
              let endRange = rcContents.range(of: endMarker),
              beginRange.upperBound <= endRange.lowerBound else { return nil }
        return String(rcContents[beginRange.upperBound..<endRange.lowerBound])
    }

    private static func replaceBlock(in rcContents: String, with block: String) -> String {
        guard let beginRange = rcContents.range(of: beginMarker),
              let endRange = rcContents.range(of: endMarker) else { return rcContents }
        // Expand to include any trailing newline after the end marker.
        var endIndex = endRange.upperBound
        if endIndex < rcContents.endIndex, rcContents[endIndex] == "\n" {
            endIndex = rcContents.index(after: endIndex)
        }
        let prefix = String(rcContents[rcContents.startIndex..<beginRange.lowerBound])
        let suffix = String(rcContents[endIndex...])
        return prefix + block + suffix
    }

    private static func quote(_ value: String) -> String {
        if value.contains(" ") || value.contains("\"") || value.isEmpty {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        return value
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
        }
        return value
    }
}
