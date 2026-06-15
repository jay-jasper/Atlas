import SwiftUI

struct TeleprompterPanel: View {
    @ObservedObject var service: TeleprompterService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Teleprompter", systemImage: "text.viewfinder")
                .font(.headline)

            TextEditor(text: $service.script)
                .font(.system(size: 13))
                .frame(height: 60)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))

            // Scrolling preview viewport.
            GeometryReader { geo in
                ScrollViewReader { _ in
                    Text(service.script)
                        .font(.system(size: CGFloat(service.fontSize), weight: .semibold))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .scaleEffect(x: service.isMirrored ? -1 : 1, y: 1)
                        .offset(y: -service.offset)
                        .background(GeometryReader { inner in
                            Color.clear.onAppear {
                                service.contentHeight = inner.size.height
                                service.viewportHeight = geo.size.height
                            }
                        })
                }
                .clipped()
            }
            .frame(height: 90)
            .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))

            HStack {
                Text("Speed").font(.caption)
                Slider(value: $service.speed, in: 10...120)
                Text("\(Int(service.speed))").font(.caption.monospacedDigit()).frame(width: 28)
            }

            HStack {
                if service.isScrolling {
                    Button("Pause") { service.pause() }
                } else {
                    Button("Play") { service.start() }.buttonStyle(.borderedProminent)
                }
                Button("Reset") { service.reset() }
                Spacer()
                Toggle("Mirror", isOn: $service.isMirrored)
                    .toggleStyle(.switch).controlSize(.mini)
            }
        }
    }
}
