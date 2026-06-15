import SwiftUI

/// Renders a Block Kit `BlockKitNode` tree as native SwiftUI. Interaction events
/// are surfaced via `onEvent` for the host to forward to the plugin.
struct BlockKitView: View {
    let node: BlockKitNode
    let onEvent: (BlockKitEvent) -> Void

    var body: some View {
        switch node {
        case .vstack(let children):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    BlockKitView(node: child, onEvent: onEvent)
                }
            }
        case .hstack(let children):
            HStack(spacing: 6) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    BlockKitView(node: child, onEvent: onEvent)
                }
            }
        case .section(let title, let children):
            VStack(alignment: .leading, spacing: 4) {
                if !title.isEmpty {
                    Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    BlockKitView(node: child, onEvent: onEvent)
                }
            }
        case .spacer:
            Spacer(minLength: 4)
        case .text(let value):
            Text(value).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
        case .image(let url):
            if let url = URL(string: url) {
                AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                    .frame(maxHeight: 120)
            }
        case .code(_, let value):
            Text(value).font(.system(.caption, design: .monospaced))
                .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        case .progress(let value):
            ProgressView(value: min(max(value, 0), 1))
        case .button(let label, let action):
            Button(label) { onEvent(.buttonClick(action: action)) }
        case .textField(let id, let placeholder):
            BlockKitTextField(id: id, placeholder: placeholder, onEvent: onEvent)
        case .toggle(let id, let label, let value):
            BlockKitToggle(id: id, label: label, initial: value, onEvent: onEvent)
        case .slider(let id, let value, let min, let max):
            BlockKitSlider(id: id, initial: value, range: min...max, onEvent: onEvent)
        case .unknown(let kind):
            Text("Unsupported node: \(kind)").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

enum BlockKitEvent: Equatable {
    case buttonClick(action: String)
    case textChanged(id: String, value: String)
    case toggleChanged(id: String, value: Bool)
    case sliderChanged(id: String, value: Double)
}

private struct BlockKitTextField: View {
    let id: String
    let placeholder: String
    let onEvent: (BlockKitEvent) -> Void
    @State private var text = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .onChange(of: text) { newValue in onEvent(.textChanged(id: id, value: newValue)) }
    }
}

private struct BlockKitToggle: View {
    let id: String
    let label: String
    let initial: Bool
    let onEvent: (BlockKitEvent) -> Void
    @State private var value: Bool

    init(id: String, label: String, initial: Bool, onEvent: @escaping (BlockKitEvent) -> Void) {
        self.id = id; self.label = label; self.initial = initial; self.onEvent = onEvent
        _value = State(initialValue: initial)
    }

    var body: some View {
        Toggle(label, isOn: $value)
            .onChange(of: value) { newValue in onEvent(.toggleChanged(id: id, value: newValue)) }
    }
}

private struct BlockKitSlider: View {
    let id: String
    let initial: Double
    let range: ClosedRange<Double>
    let onEvent: (BlockKitEvent) -> Void
    @State private var value: Double

    init(id: String, initial: Double, range: ClosedRange<Double>, onEvent: @escaping (BlockKitEvent) -> Void) {
        self.id = id; self.initial = initial; self.range = range; self.onEvent = onEvent
        _value = State(initialValue: initial)
    }

    var body: some View {
        Slider(value: $value, in: range)
            .onChange(of: value) { newValue in onEvent(.sliderChanged(id: id, value: newValue)) }
    }
}
