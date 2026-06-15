import AppKit
import SwiftUI

struct SubtitlePanel: View {
    @ObservedObject var service: SubtitleService

    private let formats: [(String, SubtitleFormat)] = [("SRT", .srt), ("VTT", .vtt)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Subtitle Tools", systemImage: "captions.bubble")
                .font(.headline)

            TextEditor(text: $service.inputText)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))

            HStack {
                Picker("From", selection: $service.sourceFormat) {
                    ForEach(formats, id: \.0) { Text($0.0).tag($0.1) }
                }
                .frame(width: 110)
                Picker("To", selection: $service.targetFormat) {
                    ForEach(formats, id: \.0) { Text($0.0).tag($0.1) }
                }
                .frame(width: 110)
                Spacer()
            }

            HStack {
                Text("Shift (ms)")
                    .font(.caption)
                TextField("0", value: $service.shiftMillis, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Button("Convert") { service.process() }
                    .buttonStyle(.borderedProminent)
                if service.cueCount > 0 {
                    Text("\(service.cueCount) cues")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !service.outputText.isEmpty {
                HStack {
                    Text("Output").font(.caption.weight(.semibold))
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(service.outputText, forType: .string)
                    }
                    .font(.caption)
                }
                ScrollView {
                    Text(service.outputText)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
            }
        }
    }
}
