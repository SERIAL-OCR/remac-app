import Foundation
import Vision
import AVFoundation
import CoreImage
import os.log

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Phase 0: Production-quality baseline metrics collector for establishing scanner performance baselines
/// Tracks per-frame metrics: OCR latency, confidence, glyph height, exposure/ISO, and stability time-to-lock
@available(iOS 13.0, *)
final class BaselineMetricsCollector {
    
    // MARK: - Types
    
    struct FrameMetrics {
        let frameId: UUID
        let timestamp: CFAbsoluteTime
        let ocrLatency: TimeInterval
        let recognitionConfidence: Float
        let averageGlyphHeight: Float
        let exposureValue: Float?
        let isoValue: Float?
        let focusMode: String
        let frameResolution: CGSize
        let processingMode: OCRProcessingMode
        let stabilityState: StabilityState
        let recognitionSettings: OCRSettings
        let failureSnapshot: Data?
        
        enum OCRProcessingMode: String, CaseIterable {
            case fast = "fast"
            case accurate = "accurate"
            case hybrid = "hybrid"
        }
        
        enum StabilityState: String, CaseIterable {
            case unstable = "unstable"
            case stabilizing = "stabilizing"
            case locked = "locked"
            case confirmed = "confirmed"
        }
    }
    
    struct OCRSettings {
        let recognitionLevel: Int
        let usesLanguageCorrection: Bool
        let recognitionLanguages: [String]
        let minimumTextHeight: Float
        let revision: Int

        init(from request: VNRecognizeTextRequest) {
            // VNRequestRevision may not be available across all SDK versions in this build environment;
            // cast to Int for stability and to avoid compiler errors.
            self.recognitionLevel = Int(request.revision)
            self.usesLanguageCorrection = request.usesLanguageCorrection
            // recognitionLanguages may be non-optional depending on SDK; assign directly for compatibility
            self.recognitionLanguages = request.recognitionLanguages
            self.minimumTextHeight = request.minimumTextHeight
            self.revision = Int(request.revision)
        }
    }
    
    struct BaselineReport {
        let sessionId: UUID
        let startTime: Date
        let endTime: Date
        let totalFrames: Int
        let averageOCRLatency: TimeInterval
        let medianOCRLatency: TimeInterval
        let p95OCRLatency: TimeInterval
        let averageConfidence: Float
        let averageGlyphHeight: Float
        let averageStabilityTimeToLock: TimeInterval
        let failureRate: Float
        let frameDropRate: Float
        let cameraSettings: CameraSettings
        let performanceInsights: [String]
    }
    
    struct CameraSettings {
        let averageExposure: Float?
        let averageISO: Float?
        let focusMode: String
        let videoFormat: String
        let frameRate: Float
    }
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.appleserialscanner.baseline", category: "MetricsCollector")
    private let sessionId = UUID()
    private let sessionStartTime = Date()
    private var frameMetrics: [FrameMetrics] = []
    private var stabilityLockTimes: [TimeInterval] = []
    private var lastStabilityChange: CFAbsoluteTime = 0
    private var currentStabilityState: FrameMetrics.StabilityState = .unstable
    
    // Thread safety
    private let metricsQueue = DispatchQueue(label: "baseline.metrics", qos: .utility)
    private let maxStoredFrames = 10000 // Prevent memory issues in long sessions
    
    // MARK: - Initialization
    
    init() {
        logger.info("BaselineMetricsCollector initialized for session: \(self.sessionId)")
        setupPerformanceMonitoring()
    }
    
    // MARK: - Public Interface
    
    /// Records comprehensive metrics for a frame processing operation
    func recordFrameMetrics(
        frameId: UUID = UUID(),
        ocrStartTime: CFAbsoluteTime,
        ocrEndTime: CFAbsoluteTime,
        recognitionResults: [VNRecognizedTextObservation],
        ocrRequest: VNRecognizeTextRequest,
        cameraMetadata: [String: Any]?,
        frameBuffer: CVPixelBuffer?,
        processingMode: FrameMetrics.OCRProcessingMode,
        stabilityState: FrameMetrics.StabilityState,
        failureSnapshot: Data? = nil
    ) {
        metricsQueue.async { [weak self] in
            guard let self = self else { return }
            
            let timestamp = CFAbsoluteTimeGetCurrent()
            let ocrLatency = ocrEndTime - ocrStartTime
            
            // Calculate recognition confidence (average of top candidates)
            let confidence = self.calculateAverageConfidence(from: recognitionResults)
            
            // Calculate average glyph height in pixels
            let glyphHeight = self.calculateAverageGlyphHeight(
                from: recognitionResults,
                frameBuffer: frameBuffer
            )
            
            // Extract camera metadata
            let (exposure, iso, focusMode) = self.extractCameraMetadata(from: cameraMetadata)
            
            // Get frame resolution
            let frameResolution = self.getFrameResolution(from: frameBuffer)
            
            // Track stability transitions
            self.trackStabilityTransition(to: stabilityState, at: timestamp)
            
            let metrics = FrameMetrics(
                frameId: frameId,
                timestamp: timestamp,
                ocrLatency: ocrLatency,
                recognitionConfidence: confidence,
                averageGlyphHeight: glyphHeight,
                exposureValue: exposure,
                isoValue: iso,
                focusMode: focusMode,
                frameResolution: frameResolution,
                processingMode: processingMode,
                stabilityState: stabilityState,
                recognitionSettings: OCRSettings(from: ocrRequest),
                failureSnapshot: failureSnapshot
            )
            
            self.storeFrameMetrics(metrics)
            self.logFrameMetrics(metrics)
        }
    }
    
    /// Generates comprehensive baseline report for the current session
    func generateBaselineReport() -> BaselineReport {
        return metricsQueue.sync {
            let endTime = Date()
            let latencies = frameMetrics.map { $0.ocrLatency }
            let confidences = frameMetrics.map { $0.recognitionConfidence }
            let glyphHeights = frameMetrics.map { $0.averageGlyphHeight }
            
            return BaselineReport(
                sessionId: sessionId,
                startTime: sessionStartTime,
                endTime: endTime,
                totalFrames: frameMetrics.count,
                averageOCRLatency: latencies.isEmpty ? 0 : latencies.reduce(0, +) / Double(latencies.count),
                medianOCRLatency: calculateMedian(latencies),
                p95OCRLatency: calculatePercentile(latencies, percentile: 0.95),
                averageConfidence: confidences.isEmpty ? 0 : confidences.reduce(0, +) / Float(confidences.count),
                averageGlyphHeight: glyphHeights.isEmpty ? 0 : glyphHeights.reduce(0, +) / Float(glyphHeights.count),
                averageStabilityTimeToLock: calculateAverageStabilityTime(),
                failureRate: calculateFailureRate(),
                frameDropRate: calculateFrameDropRate(),
                cameraSettings: generateCameraSettingsSummary(),
                performanceInsights: generatePerformanceInsights()
            )
        }
    }
    
    /// Exports metrics for detailed analysis
    func exportMetricsForAnalysis() -> Data? {
        return metricsQueue.sync { [weak self] in
            guard let self = self else { return nil }
            do {
                let exportData = [
                    "sessionId": self.sessionId.uuidString,
                    "frameMetrics": self.frameMetrics.map { metrics in
                        [
                            "frameId": metrics.frameId.uuidString,
                            "timestamp": metrics.timestamp,
                            "ocrLatency": metrics.ocrLatency,
                            "confidence": metrics.recognitionConfidence,
                            "glyphHeight": metrics.averageGlyphHeight,
                            "exposure": metrics.exposureValue as Any,
                            "iso": metrics.isoValue as Any,
                            "stabilityState": metrics.stabilityState.rawValue,
                            "processingMode": metrics.processingMode.rawValue
                        ]
                    }
                ]
                return try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
            } catch {
                logger.error("Failed to export metrics: \(error)")
                return nil
            }
        }
    }
    
    // MARK: - Private Implementation
    
    private func setupPerformanceMonitoring() {
        // Monitor memory usage and adjust storage if needed
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }
    
    private func calculateAverageConfidence(from results: [VNRecognizedTextObservation]) -> Float {
        guard !results.isEmpty else { return 0.0 }
        
        let confidences = results.compactMap { observation -> Float? in
            guard let topCandidate = observation.topCandidates(1).first else { return nil }
            return topCandidate.confidence
        }
        
        return confidences.isEmpty ? 0.0 : confidences.reduce(0, +) / Float(confidences.count)
    }
    
    private func calculateAverageGlyphHeight(
        from results: [VNRecognizedTextObservation],
        frameBuffer: CVPixelBuffer?
    ) -> Float {
        guard !results.isEmpty,
              let frameBuffer = frameBuffer else { return 0.0 }

        let frameHeight = Float(CVPixelBufferGetHeight(frameBuffer))

        let glyphHeights = results.map { observation in
            let boundingBox = observation.boundingBox
            // boundingBox.height is CGFloat; convert to Float before multiplying
            return Float(boundingBox.height) * frameHeight
        }

        return glyphHeights.isEmpty ? 0.0 : glyphHeights.reduce(0, +) / Float(glyphHeights.count)
    }

    private func extractCameraMetadata(from metadata: [String: Any]?) -> (Float?, Float?, String) {
        guard let metadata = metadata else {
            return (nil, nil, "unknown")
        }

        // Be defensive: different platforms/SDKs may provide different metadata keys
        let exposure = (metadata["Exposure"] as? Float) ?? (metadata["exposure"] as? Float) ?? (metadata["ExposureTime"] as? Float)
        let iso = metadata["ISO"] as? Float
        let focusMode = metadata["FocusMode"] as? String ?? "unknown"

        return (exposure, iso, focusMode)
    }
    
    private func getFrameResolution(from frameBuffer: CVPixelBuffer?) -> CGSize {
        guard let frameBuffer = frameBuffer else {
            return .zero
        }
        
        return CGSize(
            width: CVPixelBufferGetWidth(frameBuffer),
            height: CVPixelBufferGetHeight(frameBuffer)
        )
    }
    
    private func trackStabilityTransition(to newState: FrameMetrics.StabilityState, at timestamp: CFAbsoluteTime) {
        if currentStabilityState != newState {
            if currentStabilityState == .stabilizing && newState == .locked {
                let stabilityTime = timestamp - lastStabilityChange
                stabilityLockTimes.append(stabilityTime)
                logger.debug("Stability lock achieved in \(stabilityTime)s")
            }
            
            currentStabilityState = newState
            lastStabilityChange = timestamp
        }
    }
    
    private func storeFrameMetrics(_ metrics: FrameMetrics) {
        frameMetrics.append(metrics)
        
        // Prevent memory issues by limiting stored frames
        if frameMetrics.count > maxStoredFrames {
            frameMetrics.removeFirst(frameMetrics.count - maxStoredFrames)
            logger.warning("Frame metrics buffer reached limit, pruning old entries")
        }
    }
    
    private func logFrameMetrics(_ metrics: FrameMetrics) {
        logger.debug("""
            Frame \(metrics.frameId): OCR=\(String(format: "%.1f", metrics.ocrLatency * 1000))ms, \
            Conf=\(String(format: "%.2f", metrics.recognitionConfidence)), \
            Glyph=\(String(format: "%.1f", metrics.averageGlyphHeight))px, \
            State=\(metrics.stabilityState.rawValue)
            """)
    }
    
    // Statistical calculations
    private func calculateMedian(_ values: [TimeInterval]) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let count = sorted.count
        return count % 2 == 0
            ? (sorted[count/2 - 1] + sorted[count/2]) / 2
            : sorted[count/2]
    }
    
    private func calculatePercentile(_ values: [TimeInterval], percentile: Double) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int(Double(sorted.count - 1) * percentile)
        return sorted[index]
    }
    
    private func calculateAverageStabilityTime() -> TimeInterval {
        guard !stabilityLockTimes.isEmpty else { return 0 }
        return stabilityLockTimes.reduce(0, +) / Double(stabilityLockTimes.count)
    }
    
    private func calculateFailureRate() -> Float {
        guard !frameMetrics.isEmpty else { return 0 }
        let failures = frameMetrics.filter { $0.failureSnapshot != nil }.count
        return Float(failures) / Float(frameMetrics.count)
    }
    
    private func calculateFrameDropRate() -> Float {
        // This would need to be calculated based on expected vs actual frame rate
        // For now, return 0 as placeholder
        return 0.0
    }
    
    private func generateCameraSettingsSummary() -> CameraSettings {
        let exposures = frameMetrics.compactMap { $0.exposureValue }
        let isos = frameMetrics.compactMap { $0.isoValue }
        
        return CameraSettings(
            averageExposure: exposures.isEmpty ? nil : exposures.reduce(0, +) / Float(exposures.count),
            averageISO: isos.isEmpty ? nil : isos.reduce(0, +) / Float(isos.count),
            focusMode: frameMetrics.first?.focusMode ?? "unknown",
            videoFormat: "unknown", // Would need to be tracked separately
            frameRate: 0.0 // Would need to be calculated from timestamps
        )
    }
    
    private func generatePerformanceInsights() -> [String] {
        var insights: [String] = []
        
        let avgLatency = frameMetrics.map { $0.ocrLatency }.reduce(0, +) / Double(max(frameMetrics.count, 1))
        if avgLatency > 0.1 {
            insights.append("High OCR latency detected (avg: \(String(format: "%.1f", avgLatency * 1000))ms)")
        }
        
        let avgConfidence = frameMetrics.map { $0.recognitionConfidence }.reduce(0, +) / Float(max(frameMetrics.count, 1))
        if avgConfidence < 0.7 {
            insights.append("Low recognition confidence (avg: \(String(format: "%.2f", avgConfidence)))")
        }
        
        let avgGlyphHeight = frameMetrics.map { $0.averageGlyphHeight }.reduce(0, +) / Float(max(frameMetrics.count, 1))
        if avgGlyphHeight < 20 {
            insights.append("Small glyph size detected (avg: \(String(format: "%.1f", avgGlyphHeight))px)")
        }
        
        return insights
    }
    
    private func handleMemoryWarning() {
        metricsQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Keep only recent metrics in memory
            if self.frameMetrics.count > 1000 {
                self.frameMetrics = Array(self.frameMetrics.suffix(1000))
                self.logger.warning("Memory warning: pruned frame metrics to last 1000 entries")
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        logger.info("BaselineMetricsCollector deinitialized for session: \(self.sessionId)")
    }
}
