import AppKit
import CoreImage
import Foundation
import Vision

/// Foreground cutout: Vision subject mask → transparent PNG, auto-cropped to
/// the subject's bounding box. macOS 14+ (the mask request is unavailable
/// earlier; callers hide the entry point).
enum ScreenshotCutout {
    enum CutoutError: Error {
        case noSubject
        case renderingFailed
    }

    static var isSupported: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    @available(macOS 14.0, *)
    static func cutoutPNG(from pngData: Data) throws -> Data {
        guard let rep = NSBitmapImageRep(data: pngData), let cgImage = rep.cgImage else {
            throw CutoutError.renderingFailed
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first, observation.allInstances.isEmpty == false else {
            throw CutoutError.noSubject
        }

        let maskedBuffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: true
        )

        let ciImage = CIImage(cvPixelBuffer: maskedBuffer)
        let ciContext = CIContext()
        guard let output = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            throw CutoutError.renderingFailed
        }
        guard let png = NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:]) else {
            throw CutoutError.renderingFailed
        }
        return png
    }
}
