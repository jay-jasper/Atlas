import AVFoundation
import SwiftUI

struct CameraPreviewPanel: View {
    let permissionState: CameraPermissionState
    let onRequestAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hand Mirror")
                .font(.headline)

            switch permissionState {
            case .authorized:
                LiveCameraPreview()
                    .frame(width: 320, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            case .notDetermined:
                Button("Enable Camera", action: onRequestAccess)
            case .denied:
                Text("Camera access is denied in System Settings.")
                    .foregroundColor(.secondary)
            case .restricted:
                Text("Camera access is restricted on this Mac.")
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct LiveCameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let session = AVCaptureSession()
        session.sessionPreset = .medium

        if let device = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer = layer
        view.wantsLayer = true
        Task.detached {
            session.startRunning()
        }
        context.coordinator.session = session
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.layer?.frame = nsView.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var session: AVCaptureSession?

        deinit {
            session?.stopRunning()
        }
    }
}
