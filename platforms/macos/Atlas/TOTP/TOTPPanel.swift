import AppKit
import SwiftUI

struct TOTPPanel: View {
    @ObservedObject var service: TOTPService
    @State private var newURI: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("TOTP 2FA", systemImage: "lock.shield")
                    .font(.headline)
                Spacer()
            }

            if service.accounts.isEmpty {
                Text("No accounts yet. Paste an otpauth:// URI below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 8) {
                        ForEach(service.accounts) { account in
                            TOTPRow(
                                account: account,
                                code: service.code(for: account, at: context.date),
                                secondsRemaining: service.secondsRemaining(for: account, at: context.date),
                                onCopy: { copy(service.code(for: account, at: context.date)) },
                                onDelete: { service.delete(id: account.id) }
                            )
                        }
                    }
                }
            }

            Divider()

            HStack {
                TextField("otpauth://totp/Issuer:user?secret=…", text: $newURI)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    service.addFromURI(newURI)
                    if service.statusMessage.isEmpty { newURI = "" }
                }
                .disabled(newURI.isEmpty)
            }

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private struct TOTPRow: View {
    let account: TOTPAccount
    let code: String
    let secondsRemaining: Int
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(account.issuer).font(.subheadline.weight(.semibold))
                if !account.label.isEmpty {
                    Text(account.label).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(formattedCode)
                .font(.system(.title3, design: .monospaced))
                .onTapGesture(perform: onCopy)
            Text("\(secondsRemaining)s")
                .font(.caption.monospacedDigit())
                .foregroundStyle(secondsRemaining <= 5 ? .red : .secondary)
                .frame(width: 32, alignment: .trailing)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
    }

    private var formattedCode: String {
        guard code.count == 6 else { return code }
        let mid = code.index(code.startIndex, offsetBy: 3)
        return "\(code[code.startIndex..<mid]) \(code[mid...])"
    }
}
