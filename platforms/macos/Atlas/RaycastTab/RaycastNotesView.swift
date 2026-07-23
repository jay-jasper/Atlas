import SwiftUI

/// 笔记页:左列表(搜索/pin)+ 右 markdown 编辑器,数据在 Rust。
struct RaycastNotesView: View {
    @StateObject private var client = NotesClient()
    @State private var query = ""
    @State private var selectedID: String?
    @State private var editorTitle = ""
    @State private var editorBody = ""
    @State private var saveDebounce: Task<Void, Never>?

    private var visibleNotes: [NoteMeta] {
        query.isEmpty ? client.notes : client.search(query)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            noteList
                .frame(width: 220)
            editor
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minHeight: 420, alignment: .topLeading)
    }

    private var noteList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(loc("搜索笔记…", "Search notes…"), text: $query)
                    .textFieldStyle(.roundedBorder)
                Button {
                    createNote()
                } label: {
                    Image(systemName: "plus")
                }
                .help(loc("新建笔记", "New note"))
            }

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(visibleNotes, id: \.id) { note in
                        noteRow(note)
                    }
                }
            }
        }
    }

    private func noteRow(_ note: NoteMeta) -> some View {
        Button {
            select(note.id)
        } label: {
            HStack(spacing: 6) {
                if note.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                }
                Text(note.title.isEmpty ? loc("(无标题)", "(Untitled)") : note.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedID == note.id ? Color.accentColor.opacity(0.16) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .contextMenu {
            Button(note.pinned ? loc("取消置顶", "Unpin") : loc("置顶", "Pin")) {
                client.togglePin(id: note.id)
            }
            Button(loc("删除", "Delete"), role: .destructive) {
                client.delete(id: note.id)
                if selectedID == note.id { selectedID = nil }
            }
        }
    }

    @ViewBuilder
    private var editor: some View {
        if selectedID != nil {
            VStack(alignment: .leading, spacing: 8) {
                TextField(loc("标题", "Title"), text: $editorTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .semibold))
                    .onChange(of: editorTitle) { _ in scheduleSave() }
                Divider()
                TextEditor(text: $editorBody)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 320)
                    .onChange(of: editorBody) { _ in scheduleSave() }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        } else {
            VStack(spacing: 8) {
                Image(systemName: "note.text")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
                Text(loc("选择或新建一篇笔记", "Select or create a note"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        }
    }

    private func createNote() {
        if let id = client.save(id: nil, title: loc("新笔记", "New Note"), body: "") {
            select(id)
        }
    }

    private func select(_ id: String) {
        flushSave()
        selectedID = id
        if let note = client.note(id: id) {
            editorTitle = note.meta.title
            editorBody = note.bodyMd
        }
    }

    /// 700ms 防抖自动保存。
    private func scheduleSave() {
        saveDebounce?.cancel()
        let id = selectedID
        saveDebounce = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, let id else { return }
            client.save(id: id, title: editorTitle, body: editorBody)
        }
    }

    private func flushSave() {
        saveDebounce?.cancel()
        if let id = selectedID {
            client.save(id: id, title: editorTitle, body: editorBody)
        }
    }
}
