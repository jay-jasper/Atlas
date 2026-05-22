import SwiftUI

struct TokenBarPanel: View {
    let summary: TokenBarSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TokenBar")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("\(summary.inputTokens + summary.outputTokens) tokens")
                .font(.headline)
            Text("$\(Double(summary.costMicrosUSD) / 1_000_000, specifier: "%.4f") estimated")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
    }
}
