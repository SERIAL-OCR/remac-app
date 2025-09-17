// Cross-platform CameraPreviewView
// Provides a SwiftUI wrapper around AVCaptureSession preview for iOS and macOS.

import SwiftUI
import AVFoundation

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

#if os(iOS) || os(tvOS)
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        view.clipsToBounds = true

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.connection?.videoOrientation = .portrait
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.compactMap({ $0 as? AVCaptureVideoPreviewLayer }).first {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.frame = uiView.bounds
            CATransaction.commit()
        }
    }
}

#elseif os(macOS)
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer?.addSublayer(previewLayer)

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let layer = nsView.layer?.sublayers?.compactMap({ $0 as? AVCaptureVideoPreviewLayer }).first {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.frame = nsView.bounds
            CATransaction.commit()
        }
    }
}
#endif
