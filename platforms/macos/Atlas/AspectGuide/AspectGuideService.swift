import Foundation

@MainActor
final class AspectGuideService: ObservableObject {
    @Published var selectedPreset: AspectRatioPreset = .vertical9x16
    @Published var isOverlayVisible = false

    func toggleOverlay() {
        isOverlayVisible.toggle()
    }

    func rect(in container: CGSize) -> CGRect {
        AspectRatioGuide.fittedRect(preset: selectedPreset, in: container)
    }
}
