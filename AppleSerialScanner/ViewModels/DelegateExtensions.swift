#if os(iOS)
import UIKit
#else
import AppKit
#endif
import AVFoundation
import CoreImage

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension SerialScannerViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        Task { @MainActor in
            self.processFrame(cgImage)
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension SerialScannerViewModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let imageData = photo.fileDataRepresentation() else { return }

        #if os(iOS)
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage else { return }
        #else
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        #endif

        Task { @MainActor in
            self.processFrame(cgImage)
        }
    }
}
