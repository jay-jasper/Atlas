import AppKit
import CoreGraphics
import Foundation

struct CapturableWindow: Identifiable, Equatable {
    let id: CGWindowID
    let title: String
    let ownerName: String
    let bounds: CGRect
}

enum WindowCaptureError: LocalizedError, Equatable {
    case listFailed(String)
    case captureFailed(String)
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .listFailed(let message), .captureFailed(let message):
            return message
        case .imageEncodingFailed:
            return "Captured window image could not be encoded"
        }
    }
}

protocol WindowCaptureProviding {
    func listWindows() throws -> [CapturableWindow]
    func captureWindow(id: CGWindowID) throws -> Data
}

struct CoreGraphicsWindowCaptureProvider: WindowCaptureProviding {
    func listWindows() throws -> [CapturableWindow] {
        guard
            let rawWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else {
            throw WindowCaptureError.listFailed("Window list could not be read")
        }

        return rawWindows.compactMap(Self.capturableWindow)
    }

    static func capturableWindow(from info: [String: Any]) -> CapturableWindow? {
        guard
            let number = info[kCGWindowNumber as String] as? UInt32,
            let layer = info[kCGWindowLayer as String] as? Int,
            let ownerName = info[kCGWindowOwnerName as String] as? String,
            let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
            let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
        else {
            return nil
        }

        let title = (info[kCGWindowName as String] as? String) ?? ownerName
        guard layer == 0, bounds.width >= 32, bounds.height >= 32 else { return nil }

        return CapturableWindow(
            id: CGWindowID(number),
            title: title.isEmpty ? ownerName : title,
            ownerName: ownerName,
            bounds: bounds
        )
    }

    func captureWindow(id: CGWindowID) throws -> Data {
        guard
            let image = CGWindowListCreateImage(
                .null,
                [.optionIncludingWindow],
                id,
                [.boundsIgnoreFraming, .bestResolution]
            )
        else {
            throw WindowCaptureError.captureFailed("Selected window could not be captured")
        }

        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw WindowCaptureError.imageEncodingFailed
        }
        return data
    }
}
