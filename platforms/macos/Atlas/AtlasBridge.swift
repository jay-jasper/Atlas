import AppKit
import CoreGraphics
import Foundation

class AtlasBridge {
    static var captureService: AtlasCaptureService = .live
    static var windowCaptureProvider: WindowCaptureProviding = CoreGraphicsWindowCaptureProvider()
    static var monitoringService: MonitoringProviding = MonitoringService.live
    static var featureService: FeatureProviding = FeatureService.live
    static var ocrService: ScreenshotOCRProviding = VisionScreenshotOCRService()

    static func listFeatures() throws -> [AtlasFeature] {
        try featureService.listFeatures()
    }

    static func toggleFeature(name: String, enabled: Bool) throws -> Bool {
        try featureService.toggleFeature(name: name, enabled: enabled)
    }

    static func startMonitoring(callback: @escaping (MonitoringSystemSnapshot) -> Void) throws {
        try monitoringService.startMonitoring(callback: callback)
    }

    static func stopMonitoring() throws {
        try monitoringService.stopMonitoring()
    }

    static func lookupPort(_ port: UInt16) throws -> MonitoringPortProcess? {
        try monitoringService.lookupPort(port)
    }

    static func killPortProcess(pid: UInt32) throws -> Bool {
        try monitoringService.killPortProcess(pid)
    }

    static func captureRegion(x: Int32, y: Int32, width: UInt32, height: UInt32) throws -> Data {
        try captureService.captureRegion(x, y, width, height)
    }

    static func captureFullScreen() throws -> Data {
        try captureService.captureFullScreen()
    }

    static func listCapturableWindows() throws -> [CapturableWindow] {
        try windowCaptureProvider.listWindows()
    }

    static func captureWindow(id: CGWindowID) throws -> Data {
        try windowCaptureProvider.captureWindow(id: id)
    }

    static func recognizeText(in imageData: Data) throws -> ScreenshotOCRResult {
        try ocrService.recognizeText(in: imageData)
    }
}
