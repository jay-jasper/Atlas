import SwiftUI

/// Raycast tab:全部新功能收在这里(用户决策)。侧栏 + 右详情,
/// 布局与 PluginsTab 同构。
struct RaycastTab: View {
    enum Selection: String, CaseIterable, Identifiable {
        case snippets
        case notes
        case focus
        case translate
        case aiCommands
        case dictation
        case systemCommands
        case calendar
        case hyperKey
        case transfer

        var id: String { rawValue }

        var title: String {
            switch self {
            case .snippets: return loc("片段", "Snippets")
            case .notes: return loc("笔记", "Notes")
            case .focus: return loc("专注", "Focus")
            case .translate: return loc("翻译", "Translate")
            case .aiCommands: return loc("AI 指令", "AI Commands")
            case .dictation: return loc("听写", "Dictation")
            case .systemCommands: return loc("系统命令", "System Commands")
            case .calendar: return loc("日历", "Calendar")
            case .hyperKey: return "Hyper Key"
            case .transfer: return loc("导入导出", "Import & Export")
            }
        }

        var icon: String {
            switch self {
            case .snippets: return "text.badge.plus"
            case .notes: return "note.text"
            case .focus: return "timer"
            case .translate: return "character.bubble"
            case .aiCommands: return "wand.and.stars"
            case .dictation: return "mic"
            case .systemCommands: return "switch.2"
            case .calendar: return "calendar"
            case .hyperKey: return "keyboard"
            case .transfer: return "arrow.up.arrow.down.square"
            }
        }
    }

    @State private var selection: Selection = .snippets

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 210)
            Divider().opacity(0.35)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("Raycast")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                ForEach(Selection.allCases) { entry in
                    sidebarRow(entry)
                }
            }
            .padding(8)
        }
    }

    private func sidebarRow(_ target: Selection) -> some View {
        Button {
            selection = target
        } label: {
            HStack(spacing: 8) {
                Image(systemName: target.icon)
                    .font(.system(size: 12))
                    .frame(width: 18)
                Text(target.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selection == target ? Color.accentColor.opacity(0.16) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    @ViewBuilder
    private var detail: some View {
        ScrollView {
            Group {
                switch selection {
                case .snippets: RaycastSnippetsView()
                case .notes: RaycastNotesView()
                case .focus: RaycastFocusView()
                case .translate: RaycastTranslateView()
                case .aiCommands: RaycastAICommandsView()
                case .dictation: RaycastDictationView()
                case .systemCommands: RaycastSystemCommandsView()
                case .calendar: RaycastCalendarView()
                case .hyperKey: RaycastHyperKeyView()
                case .transfer: RaycastTransferView()
                }
            }
            .padding(18)
            .frame(maxWidth: 640, alignment: .topLeading)
        }
    }
}
