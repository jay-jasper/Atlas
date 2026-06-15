import Foundation

/// Writes files that require administrator privileges (e.g. `/etc/hosts`).
/// Strategy: write the new content to an unprivileged temp file, then copy it
/// into place via `osascript ... with administrator privileges`, which shows the
/// system admin-password prompt. The command construction is pure & testable;
/// this avoids needing a separately-signed SMAppService helper target.
enum PrivilegedWrite {
    /// The AppleScript source that copies `tempPath` over `destPath` as root.
    static func copyScript(tempPath: String, destPath: String) -> String {
        // Single-quote the paths and escape any embedded single quotes for shell.
        let src = shellQuote(tempPath)
        let dst = shellQuote(destPath)
        return "do shell script \"/bin/cp \" & quoted form of \"\(src)\" & \" \" & quoted form of \"\(dst)\" with administrator privileges"
    }

    /// Shell-safe single-quoting.
    static func shellQuote(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "'\\''")
    }
}

protocol PrivilegedWriting {
    func write(_ content: String, to destinationPath: String) throws
}

enum PrivilegedWriteError: LocalizedError {
    case tempWriteFailed
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .tempWriteFailed: return "Could not stage the file before elevation."
        case .authorizationDenied: return "Administrator authorization was denied."
        }
    }
}

struct AppleScriptPrivilegedWriter: PrivilegedWriting {
    func write(_ content: String, to destinationPath: String) throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlas-priv-\(UUID().uuidString)")
        guard (try? content.write(to: temp, atomically: true, encoding: .utf8)) != nil else {
            throw PrivilegedWriteError.tempWriteFailed
        }
        defer { try? FileManager.default.removeItem(at: temp) }

        let source = PrivilegedWrite.copyScript(tempPath: temp.path, destPath: destinationPath)
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if error != nil { throw PrivilegedWriteError.authorizationDenied }
    }
}
