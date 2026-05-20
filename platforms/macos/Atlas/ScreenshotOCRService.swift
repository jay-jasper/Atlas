import AppKit
import Vision

struct ScreenshotOCRResult: Equatable {
    let lines: [String]

    var text: String {
        lines.joined(separator: "\n")
    }

    init(lines: [String]) {
        self.lines = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

protocol ScreenshotOCRProviding {
    func recognizeText(in imageData: Data) throws -> ScreenshotOCRResult
}

enum ScreenshotOCRError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Screenshot image could not be decoded for OCR"
        }
    }
}

struct VisionScreenshotOCRService: ScreenshotOCRProviding {
    func recognizeText(in imageData: Data) throws -> ScreenshotOCRResult {
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ScreenshotOCRError.invalidImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let lines = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }

        return ScreenshotOCRResult(lines: lines)
    }
}
