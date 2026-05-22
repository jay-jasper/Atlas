import AppKit
import SwiftUI

enum KeyPressResultCompatible {
    case handled
    case ignored
}

struct KeyPressModifier: ViewModifier {
    let key: KeyEquivalent
    let action: () -> KeyPressResultCompatible

    @State private var monitor: Any?

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.onKeyPress(key) {
                action() == .handled ? .handled : .ignored
            }
        } else {
            content
                .onAppear {
                    if monitor == nil {
                        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                            if matches(event) {
                                if action() == .handled {
                                    return nil // consumed
                                }
                            }
                            return event
                        }
                    }
                }
                .onDisappear {
                    if let monitor {
                        NSEvent.removeMonitor(monitor)
                        self.monitor = nil
                    }
                }
        }
    }

    private func matches(_ event: NSEvent) -> Bool {
        switch key {
        case .escape:
            return event.keyCode == 53
        case .upArrow:
            return event.keyCode == 126
        case .downArrow:
            return event.keyCode == 125
        case .return:
            return event.keyCode == 36 || event.keyCode == 76
        case .tab:
            return event.keyCode == 48
        default:
            return false
        }
    }
}

extension View {
    func onKeyPressCompatible(_ key: KeyEquivalent, action: @escaping () -> KeyPressResultCompatible) -> some View {
        self.modifier(KeyPressModifier(key: key, action: action))
    }
}

struct CommandPaletteView: View {
    let providers: [CommandProviding]
    let onDismiss: () -> Void
    private let usageRecorder: CommandUsageRecording

    // Injected closure builders for sub-views
    let screenshotLibraryViewBuilder: (() -> AnyView)?
    let portLookupViewBuilder: (() -> AnyView)?
    let windowPickerViewBuilder: (() -> AnyView)?

    @State private var query: String = ""
    @State private var stack: [PaletteDestination] = []
    @State private var selectedIndex: Int = 0

    private var results: [PaletteCommand] {
        let records = usageRecorder.usageRecords()
        return providers.flatMap { provider in
            CommandPaletteRanker.ranked(provider.results(for: query), records: records)
        }
    }

    init(
        providers: [CommandProviding],
        onDismiss: @escaping () -> Void,
        usageRecorder: CommandUsageRecording = CommandUsageStore(),
        screenshotLibraryViewBuilder: (() -> AnyView)? = nil,
        portLookupViewBuilder: (() -> AnyView)? = nil,
        windowPickerViewBuilder: (() -> AnyView)? = nil
    ) {
        self.providers = providers
        self.onDismiss = onDismiss
        self.usageRecorder = usageRecorder
        self.screenshotLibraryViewBuilder = screenshotLibraryViewBuilder
        self.portLookupViewBuilder = portLookupViewBuilder
        self.windowPickerViewBuilder = windowPickerViewBuilder
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            if stack.isEmpty {
                resultsList
                    .transition(.move(edge: .trailing))
            } else if let dest = stack.last {
                subView(for: dest)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 360)
                    .transition(.move(edge: .trailing))
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 16, y: 6)
        .onKeyPressCompatible(.escape) {
            if stack.isEmpty {
                onDismiss()
            } else {
                withAnimation(.easeInOut(duration: 0.18)) { _ = stack.removeLast() }
            }
            return .handled
        }
    }

    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField(stack.isEmpty ? "Search Atlas…" : "Filter…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .onSubmit { executeSelected() }
                .onChange(of: query) { _ in selectedIndex = 0 }
            if !stack.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { _ = stack.removeLast() }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    @ViewBuilder
    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results.indices, id: \.self) { i in
                        ResultRow(
                            command: results[i],
                            isSelected: i == selectedIndex
                        )
                        .id(i)
                        .onTapGesture { execute(results[i]) }
                    }
                }
            }
            .frame(maxHeight: 8 * 52)
            .onKeyPressCompatible(.upArrow) {
                if selectedIndex > 0 {
                    selectedIndex -= 1
                    proxy.scrollTo(selectedIndex, anchor: .center)
                }
                return .handled
            }
            .onKeyPressCompatible(.downArrow) {
                if selectedIndex < results.count - 1 {
                    selectedIndex += 1
                    proxy.scrollTo(selectedIndex, anchor: .center)
                }
                return .handled
            }
            .onKeyPressCompatible(.return) {
                executeSelected()
                return .handled
            }
            .onKeyPressCompatible(.tab) {
                executeSelected()
                return .handled
            }
        }
    }

    @ViewBuilder
    private func subView(for dest: PaletteDestination) -> some View {
        switch dest {
        case .screenshotLibrary:
            screenshotLibraryViewBuilder?() ?? AnyView(Text("Screenshot Library").padding())
        case .portLookup:
            portLookupViewBuilder?() ?? AnyView(Text("Port Lookup").padding())
        case .windowPicker:
            windowPickerViewBuilder?() ?? AnyView(Text("Window Picker").padding())
        }
    }

    private func executeSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        execute(results[selectedIndex])
    }

    private func execute(_ command: PaletteCommand) {
        usageRecorder.recordUsage(for: command)

        switch command.action {
        case .execute(let fn):
            fn()
            onDismiss()
        case .push(let dest):
            withAnimation(.easeInOut(duration: 0.18)) {
                stack.append(dest)
                query = ""
                selectedIndex = 0
            }
        }
    }
}

private struct ResultRow: View {
    let command: PaletteCommand
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            iconView
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.body)
                if let subtitle = command.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(command.category)
                .font(.caption)
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
    }

    @ViewBuilder
    private var iconView: some View {
        switch command.icon {
        case .sfSymbol(let name):
            Image(systemName: name)
                .font(.system(size: 16))
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))
        case .appIcon(let url):
            AppIconView(url: url)
        }
    }
}

private struct AppIconView: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app")
                    .font(.system(size: 16))
            }
        }
        .frame(width: 32, height: 32)
        .task(id: url) {
            // Offload disk I/O and icon rendering from the Main Actor to avoid UI stutters.
            let loadedIcon = await Task.detached(priority: .userInitiated) {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = CGSize(width: 32, height: 32)
                return icon
            }.value
            
            self.image = loadedIcon
        }
    }
}
