import CoreGraphics
import Foundation
import Vision

// MARK: - Model

/// One region the auto-redaction pass wants to cover.
struct RedactionCandidate: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case email
        case phone
        case cardNumber
        case apiKey
        case ipAddress
        case face

        var id: String { rawValue }

        var localizedTitle: String {
            switch self {
            case .email: return "邮箱"
            case .phone: return "手机号"
            case .cardNumber: return "银行卡号"
            case .apiKey: return "API 密钥"
            case .ipAddress: return "IP 地址"
            case .face: return "人脸"
            }
        }
    }

    let kind: Kind
    /// Vision-style normalized bounding box (origin bottom-left, 0…1).
    let boundingBox: CGRect
    let matchedText: String?
}

// MARK: - PII classification (pure, unit-testable)

enum PIIClassifier {
    /// Categories enabled for a classification pass.
    struct Options: Equatable {
        var email = true
        var phone = true
        var cardNumber = true
        var apiKey = true
        var ipAddress = true

        static let all = Options()
    }

    private static let emailRegex = try! NSRegularExpression(
        pattern: #"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
    )
    /// International (+n…) or mainland-China (1[3-9]xxxxxxxxx) mobile numbers,
    /// tolerant of spaces/dashes inside.
    private static let phoneRegex = try! NSRegularExpression(
        pattern: #"(?<![\dA-Za-z])(\+\d{1,3}[\s-]?)?(1[3-9]\d[\s-]?\d{4}[\s-]?\d{4}|\d{3}[\s-]\d{3,4}[\s-]\d{4})(?![\dA-Za-z])"#
    )
    private static let cardRegex = try! NSRegularExpression(
        pattern: #"(?<![\dA-Za-z])(\d[ -]?){12,18}\d(?![\dA-Za-z])"#
    )
    /// Common secret prefixes, or long high-entropy token-looking strings.
    private static let apiKeyRegex = try! NSRegularExpression(
        pattern: #"(sk-[A-Za-z0-9_-]{16,}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,})"#
    )
    private static let ipRegex = try! NSRegularExpression(
        pattern: #"(?<![\d.])((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(?![\d.])"#
    )

    struct Match: Equatable {
        let kind: RedactionCandidate.Kind
        let range: Range<String.Index>
        let text: String
    }

    /// Classify one line of recognized text. Returns non-overlapping matches,
    /// earlier/more-specific kinds winning on overlap.
    static func matches(in line: String, options: Options = .all) -> [Match] {
        var results: [Match] = []
        let nsLine = line as NSString
        let full = NSRange(location: 0, length: nsLine.length)

        func collect(_ regex: NSRegularExpression, _ kind: RedactionCandidate.Kind, filter: ((String) -> Bool)? = nil) {
            for match in regex.matches(in: line, range: full) {
                guard let range = Range(match.range, in: line) else { continue }
                let text = String(line[range])
                if let filter, filter(text) == false { continue }
                let overlaps = results.contains { existing in
                    existing.range.overlaps(range)
                }
                if overlaps == false {
                    results.append(Match(kind: kind, range: range, text: text))
                }
            }
        }

        // Order matters: specific kinds first so e.g. an API key isn't half
        // claimed as a phone number.
        if options.apiKey { collect(apiKeyRegex, .apiKey) }
        if options.email { collect(emailRegex, .email) }
        if options.cardNumber {
            collect(cardRegex, .cardNumber) { candidate in
                passesLuhn(candidate.filter(\.isNumber))
            }
        }
        if options.phone { collect(phoneRegex, .phone) }
        if options.ipAddress { collect(ipRegex, .ipAddress) }

        return results.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// Luhn checksum for card-number validation.
    static func passesLuhn(_ digits: String) -> Bool {
        guard digits.count >= 13, digits.count <= 19, digits.allSatisfy(\.isNumber) else { return false }
        var sum = 0
        for (index, char) in digits.reversed().enumerated() {
            guard var value = char.wholeNumberValue else { return false }
            if index % 2 == 1 {
                value *= 2
                if value > 9 { value -= 9 }
            }
            sum += value
        }
        return sum % 10 == 0
    }

    /// Sub-box for a match inside a full-line bounding box, assuming roughly
    /// uniform glyph width (good enough for redaction cover).
    static func subBox(lineBox: CGRect, line: String, range: Range<String.Index>) -> CGRect {
        let total = line.count
        guard total > 0 else { return lineBox }
        let startOffset = line.distance(from: line.startIndex, to: range.lowerBound)
        let length = line.distance(from: range.lowerBound, to: range.upperBound)
        let startFraction = CGFloat(startOffset) / CGFloat(total)
        let widthFraction = CGFloat(length) / CGFloat(total)
        return CGRect(
            x: lineBox.minX + lineBox.width * startFraction,
            y: lineBox.minY,
            width: lineBox.width * widthFraction,
            height: lineBox.height
        )
    }
}

// MARK: - Coordinate mapping (pure, unit-testable)

enum RedactionCoordinateMapper {
    /// Vision normalized box (bottom-left origin) → canvas rect (top-left
    /// origin) inside the fitted image rect the editor displays.
    static func canvasRect(
        normalized: CGRect,
        renderedImageRect: CGRect
    ) -> CGRect {
        CGRect(
            x: renderedImageRect.minX + normalized.minX * renderedImageRect.width,
            y: renderedImageRect.minY + (1 - normalized.maxY) * renderedImageRect.height,
            width: normalized.width * renderedImageRect.width,
            height: normalized.height * renderedImageRect.height
        )
    }

    /// The aspect-fit rect of an image inside a canvas (same math the editor
    /// and renderer use).
    static func fittedImageRect(imageSize: CGSize, canvasSize: CGSize) -> CGRect {
        guard canvasSize.width > 0, canvasSize.height > 0,
              imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: imageSize)
        }
        let scale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (canvasSize.width - size.width) / 2,
            y: (canvasSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - Detection service (Vision)

/// Detects sensitive regions (PII text + faces) in a screenshot.
struct ScreenshotRedactionService {
    struct Settings: Equatable {
        var pii = PIIClassifier.Options.all
        var faces = true
    }

    var settings: Settings = Settings()

    /// Runs text recognition + face detection and returns normalized candidates.
    func detect(in image: CGImage) throws -> [RedactionCandidate] {
        var candidates: [RedactionCandidate] = []

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = false

        var requests: [VNRequest] = [textRequest]
        let faceRequest = VNDetectFaceRectanglesRequest()
        if settings.faces {
            requests.append(faceRequest)
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform(requests)

        for observation in textRequest.results ?? [] {
            guard let top = observation.topCandidates(1).first else { continue }
            let line = top.string
            for match in PIIClassifier.matches(in: line, options: settings.pii) {
                let box = PIIClassifier.subBox(
                    lineBox: observation.boundingBox,
                    line: line,
                    range: match.range
                )
                candidates.append(RedactionCandidate(kind: match.kind, boundingBox: box, matchedText: match.text))
            }
        }

        if settings.faces {
            for face in faceRequest.results ?? [] {
                candidates.append(RedactionCandidate(kind: .face, boundingBox: face.boundingBox, matchedText: nil))
            }
        }

        return candidates
    }
}
