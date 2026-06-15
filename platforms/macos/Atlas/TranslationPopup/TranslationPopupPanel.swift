import SwiftUI

struct TranslationPopupPanel: View {
    @ObservedObject var service: TranslationPopupService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Translation", systemImage: "character.bubble")
                    .font(.headline)
                Spacer()
                Picker("", selection: $service.targetLanguage) {
                    ForEach(TranslationPopupService.languages, id: \.code) { Text($0.name).tag($0.code) }
                }
                .frame(width: 110)
            }

            TextEditor(text: $service.sourceText)
                .font(.system(size: 12))
                .frame(height: 50)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))

            HStack {
                Button("Translate") { service.translate() }
                    .buttonStyle(.borderedProminent)
                Button("From Clipboard") { service.translateSelection() }
                    .controlSize(.small)
            }

            if !service.translatedText.isEmpty {
                HStack {
                    Text("Result").font(.caption.weight(.semibold))
                    Spacer()
                    Button("Copy") { service.copyResult() }.font(.caption)
                }
                Text(service.translatedText)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .textSelection(.enabled)
            }

            if !service.statusMessage.isEmpty {
                Text(service.statusMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
