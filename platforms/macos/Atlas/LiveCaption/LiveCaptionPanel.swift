import SwiftUI

struct LiveCaptionPanel: View {
    @ObservedObject var service: LiveCaptionService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Live Caption", systemImage: "captions.bubble.fill")
                    .font(.headline)
                Spacer()
                if service.isCaptioning {
                    Button("Stop") { service.stop() }.controlSize(.small)
                } else {
                    Button("Start") { service.start() }.controlSize(.small).buttonStyle(.borderedProminent)
                }
            }

            Text(service.caption.isEmpty ? "Captions will appear here as you speak." : service.caption)
                .font(.callout)
                .foregroundStyle(service.caption.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                .padding(10)
                .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white)

            HStack {
                if !service.caption.isEmpty {
                    Button("Clear") { service.clear() }.controlSize(.small)
                }
                Spacer()
            }

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
