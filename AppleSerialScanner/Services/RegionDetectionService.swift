import Foundation
import CoreImage
import os.log

@available(iOS 13.0, *)
final class RegionDetectionService: ObservableObject {
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "RegionDetectionService")
    private let mlDetector = SerialRegionDetector()
    private let smartFallback = SmartROIDetector()
    
    struct RegionDetectionOutcome {
        let boxes: [CGRect]
        let confidences: [Float]
        let stabilizedROI: CGRect?
        let usedFallback: Bool
    }
    
    func detectRegions(
        pixelBuffer: CVPixelBuffer,
        imageSize: CGSize,
        visionText: [VNRecognizedTextObservation] = []
    ) async -> RegionDetectionOutcome {
        // Try ML detector first
        do {
            let mlResult = try await mlDetector.detectSerialRegions(in: pixelBuffer, imageSize: imageSize)
            // Optionally fuse with Vision
            let fused = mlDetector.fuseWithVisionResults(
                detectionResult: mlResult,
                visionObservations: visionText,
                imageSize: imageSize
            )
            return RegionDetectionOutcome(
                boxes: fused.boundingBoxes,
                confidences: fused.confidences,
                stabilizedROI: fused.stabilizedROI,
                usedFallback: false
            )
        } catch {
            logger.error("ML region detection failed, falling back: \(error.localizedDescription)")
        }
        
        // Fallback to heuristic ROI strategy
        let roiResult = smartFallback.detectOptimalROI(
            deviceType: nil,
            surfaceType: .unknown,
            scanningMode: .screen,
            imageSize: imageSize
        )
        
        return RegionDetectionOutcome(
            boxes: roiResult.allROIs,
            confidences: Array(repeating: roiResult.confidence, count: roiResult.allROIs.count),
            stabilizedROI: roiResult.primaryROI,
            usedFallback: true
        )
    }
}

