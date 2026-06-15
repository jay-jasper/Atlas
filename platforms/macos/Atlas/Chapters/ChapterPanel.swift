import AppKit
import SwiftUI

struct ChapterPanel: View {
    @ObservedObject var service: ChapterService
    @State private var draftTitle = ""
    @State private var exportFormat: ChapterExporter.Format = .youtube

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Chapter Markers", systemImage: "bookmark.square")
                    .font(.headline)
                Spacer()
                if service.isRecording {
                    Text(ChapterExporter.timestamp(service.elapsed, includeHours: false))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.red)
                }
            }

            if service.isRecording {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Color.clear.frame(height: 0).onAppear { service.tick() }
                }
            }

            HStack {
                if service.isRecording {
                    Button("Stop") { service.stop() }
                    TextField("Marker title", text: $draftTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addMarker() }
                    Button("Mark") { addMarker() }
                } else {
                    Button("Start Recording") { service.start() }
                        .buttonStyle(.borderedProminent)
                }
            }

            ForEach(service.markers) { marker in
                HStack {
                    Text(ChapterExporter.timestamp(marker.seconds, includeHours: false))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(marker.title).font(.caption)
                    Spacer()
                    Button(role: .destructive) { service.remove(id: marker.id) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
            }

            if !service.markers.isEmpty {
                Divider()
                HStack {
                    Picker("", selection: $exportFormat) {
                        ForEach(ChapterExporter.Format.allCases, id: \.self) {
                            Text($0.rawValue.capitalized).tag($0)
                        }
                    }
                    .frame(width: 110)
                    Button("Copy Export") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(service.export(as: exportFormat), forType: .string)
                    }
                }
            }
        }
    }

    private func addMarker() {
        service.mark(title: draftTitle)
        draftTitle = ""
    }
}
