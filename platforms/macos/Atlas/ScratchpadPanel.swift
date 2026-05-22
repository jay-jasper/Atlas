import SwiftUI

struct ScratchpadPanel: View {
    let store: ScratchpadStoring
    let summarizer: ScratchpadSummarizing
    let initialSelectedNoteID: UUID?

    @State private var notes: [ScratchpadNote] = []
    @State private var selectedID: UUID?
    @State private var draft = ScratchpadDraft(title: "", markdown: "")
    @State private var query: String = ""
    @State private var summaryText: String = ""
    @State private var statusText: String = ""
    @State private var isSummarizing = false

    init(
        store: ScratchpadStoring,
        summarizer: ScratchpadSummarizing,
        initialSelectedNoteID: UUID? = nil
    ) {
        self.store = store
        self.summarizer = summarizer
        self.initialSelectedNoteID = initialSelectedNoteID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Scratchpad", systemImage: "note.text")
                    .font(.headline)
                Spacer()
                Button {
                    newNote()
                } label: {
                    Label("New", systemImage: "plus")
                }
            }

            TextField("Search notes", text: $query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: query) { _ in loadNotes() }

            HStack(alignment: .top, spacing: 12) {
                List(notes, selection: $selectedID) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(note.markdown)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .tag(note.id)
                }
                .frame(minWidth: 140, minHeight: 220)
                .onChange(of: selectedID) { _ in selectCurrentNote() }

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Title", text: $draft.title)
                        .textFieldStyle(.roundedBorder)

                    TextEditor(text: $draft.markdown)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 180)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.25))
                        )

                    HStack {
                        Button {
                            saveDraft()
                        } label: {
                            Label(selectedID == nil ? "Create" : "Save", systemImage: "square.and.arrow.down")
                        }
                        .disabled(!draft.isValid)

                        Button(role: .destructive) {
                            deleteSelectedNote()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(selectedID == nil)

                        Spacer()

                        Button {
                            summarizeSelectedNote()
                        } label: {
                            Label("Summarize", systemImage: "sparkles")
                        }
                        .disabled(selectedNote == nil || isSummarizing)
                    }
                }
            }

            if !summaryText.isEmpty {
                Text(summaryText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !statusText.isEmpty {
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            selectedID = initialSelectedNoteID
            loadNotes()
        }
    }

    private var selectedNote: ScratchpadNote? {
        guard let selectedID else { return nil }
        return notes.first { $0.id == selectedID }
    }

    private func loadNotes() {
        do {
            notes = try store.search(query)
            if let selectedID, !notes.contains(where: { $0.id == selectedID }) {
                self.selectedID = notes.first?.id
            }
            selectCurrentNote()
            statusText = ""
        } catch {
            notes = []
            statusText = error.localizedDescription
        }
    }

    private func selectCurrentNote() {
        guard let selectedNote else { return }
        draft = ScratchpadDraft(title: selectedNote.title, markdown: selectedNote.markdown)
        summaryText = ""
    }

    private func newNote() {
        selectedID = nil
        draft = ScratchpadDraft(title: "", markdown: "")
        summaryText = ""
        statusText = ""
    }

    private func saveDraft() {
        do {
            let saved: ScratchpadNote
            if let selectedID {
                saved = try store.update(id: selectedID, draft: draft)
            } else {
                saved = try store.create(draft)
            }
            selectedID = saved.id
            loadNotes()
            statusText = "Saved"
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func deleteSelectedNote() {
        guard let selectedID else { return }
        do {
            try store.delete(id: selectedID)
            self.selectedID = nil
            draft = ScratchpadDraft(title: "", markdown: "")
            summaryText = ""
            loadNotes()
            statusText = "Deleted"
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func summarizeSelectedNote() {
        guard let note = selectedNote else { return }
        isSummarizing = true
        summaryText = ""

        Task { @MainActor in
            do {
                if let result = try await summarizer.summarize(note: note) {
                    summaryText = result.summary
                } else {
                    summaryText = "Summary is not configured."
                }
            } catch {
                summaryText = error.localizedDescription
            }
            isSummarizing = false
        }
    }
}
