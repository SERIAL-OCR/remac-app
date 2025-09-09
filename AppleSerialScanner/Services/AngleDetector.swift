import Foundation
import CoreImage
import Vision
#if os(iOS)
import CoreMotion
#endif

/// Text orientation information for angle correction
struct TextOrientation: Equatable {
    let rotationAngle: Float      // Rotation angle in degrees (-180 to 180)
    let skewAngle: Float         // Skew correction angle in degrees
    let confidence: Float        // Detection confidence (0.0 to 1.0)
    let textBounds: CGRect       // Bounding rectangle of detected text
    let timestamp: Date          // When detection was performed

    /// Initialize with default values
    init(rotationAngle: Float = 0.0,
         skewAngle: Float = 0.0,
         confidence: Float = 0.0,
         textBounds: CGRect = .zero) {
        self.rotationAngle = rotationAngle
        self.skewAngle = skewAngle
        self.confidence = confidence
        self.textBounds = textBounds
        self.timestamp = Date()
    }
}

/// Perspective information for distortion correction
struct PerspectiveInfo {
    let transform: CGAffineTransform  // Perspective correction matrix
    let confidence: Float            // Correction confidence
    let vanishingPoint: CGPoint?     // Detected vanishing point
}

/// Advanced angle detection and correction system
class AngleDetector: ObservableObject {
    // MARK: - Published Properties
    @Published var currentAngle: Float = 0.0
    @Published var isAngleOptimal: Bool = true
    @Published var angleWarning: String = ""

    // MARK: - Properties
    private let context = CIContext()
    #if os(iOS)
    private var motionManager: CMMotionManager?
    #endif
    private var deviceOrientation: Float = 0.0

    // MARK: - Initialization

    init() {
        setupMotionManager()
    }

    deinit {
        #if os(iOS)
        motionManager?.stopDeviceMotionUpdates()
        #endif
    }

    private func setupMotionManager() {
        #if os(iOS)
        motionManager = CMMotionManager()
        motionManager?.deviceMotionUpdateInterval = 1.0 / 30.0  // 30Hz updates

        motionManager?.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion, error == nil else { return }

            // Get device attitude (orientation in 3D space)
            let attitude = motion.attitude
            self.deviceOrientation = Float(attitude.yaw * 180.0 / .pi)
        }
        #endif
    }

    // MARK: - Text Orientation Detection

    /// Detect text orientation using Vision framework
    func detectTextOrientation(in image: CIImage) -> TextOrientation {
        let request = VNDetectTextRectanglesRequest()

        // Configure for accurate text detection
        request.reportCharacterBoxes = true

        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            return TextOrientation(confidence: 0.0)
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])

            guard let results = request.results, !results.isEmpty else {
                return TextOrientation(confidence: 0.0)
            }

            return analyzeTextRectangles(results)
        } catch {
            AppLogger.vision.error("Text detection failed: \(error.localizedDescription)")
            return TextOrientation(confidence: 0.0)
        }
    }

    /// Analyze detected text rectangles to determine orientation
    private func analyzeTextRectangles(_ rectangles: [VNTextObservation]) -> TextOrientation {
        var angles: [Float] = []
        var allBounds = CGRect.zero

        for observation in rectangles {
            // VNTextObservation is already the correct type, no need for conditional cast
            let bounds = observation.boundingBox

            // Calculate angle from rectangle orientation
            let angle = calculateAngleFromRectangle(bounds)
            angles.append(angle)

            // Expand overall bounds
            allBounds = allBounds.union(bounds)
        }

        guard !angles.isEmpty else {
            return TextOrientation(confidence: 0.0)
        }

        // Calculate average angle and confidence
        let averageAngle = angles.reduce(0, +) / Float(angles.count)
        let angleVariance = calculateVariance(angles, mean: averageAngle)
        let confidence = calculateConfidence(from: angleVariance, textCount: angles.count)

        return TextOrientation(
            rotationAngle: averageAngle,
            skewAngle: 0.0, // Will be calculated separately
            confidence: confidence,
            textBounds: allBounds
        )
    }

    /// Calculate rotation angle from text rectangle bounds
    private func calculateAngleFromRectangle(_ bounds: CGRect) -> Float {
        // For text rectangles, the angle can be derived from the aspect ratio and orientation
        // This is a simplified implementation - production would use more sophisticated analysis

        let width = bounds.width
        let height = bounds.height

        // If width > height, text is likely horizontal (0° or 180°)
        // If height > width, text might be vertical (90° or 270°)
        if width > height * 1.5 {
            return 0.0  // Horizontal text
        } else if height > width * 1.5 {
            return 90.0 // Vertical text
        } else {
            return 0.0  // Assume horizontal for ambiguous cases
        }
    }

    /// Calculate variance of angle measurements
    private func calculateVariance(_ values: [Float], mean: Float) -> Float {
        let squaredDifferences = values.map { pow($0 - mean, 2) }
        return squaredDifferences.reduce(0, +) / Float(values.count)
    }

    /// Calculate confidence based on variance and text count
    private func calculateConfidence(from variance: Float, textCount: Int) -> Float {
        // Lower variance = higher confidence
        let varianceConfidence = max(0.0, 1.0 - variance / 100.0)

        // More text detections = higher confidence
        let countConfidence = min(1.0, Float(textCount) / 10.0)

        return min(varianceConfidence, countConfidence)
    }

    // MARK: - Perspective Analysis

    /// Analyze perspective distortion in the image
    func analyzePerspective(in image: CIImage) -> PerspectiveInfo {
        // Simplified perspective analysis
        // Production would use vanishing point detection and homography estimation

        let transform = CGAffineTransform.identity
        let confidence = calculatePerspectiveConfidence(in: image)

        return PerspectiveInfo(
            transform: transform,
            confidence: confidence,
            vanishingPoint: nil
        )
    }

    /// Calculate confidence in perspective correction
    private func calculatePerspectiveConfidence(in image: CIImage) -> Float {
        // Simplified confidence calculation
        // Production would analyze edge consistency and vanishing points
        return 0.7
    }

    // MARK: - Rotation Correction

    /// Apply rotation correction to an image
    func correctRotation(in image: CIImage, for orientation: TextOrientation) -> CIImage {
        guard orientation.confidence > 0.5 else {
            return image // Don't correct if confidence is too low
        }

        let angleInRadians = CGFloat(orientation.rotationAngle) * .pi / 180.0

        // Create rotation transform
        let transform = CGAffineTransform(rotationAngle: -angleInRadians)

        // Apply transform to image
        return image.transformed(by: transform)
    }

    // MARK: - Device Orientation Integration

    /// Get current device orientation relative to gravity
    func getDeviceOrientation() -> Float {
        return deviceOrientation
    }

    /// Calculate optimal viewing angle for text
    func calculateOptimalAngle(for textOrientation: TextOrientation) -> Float {
        let deviceAngle = getDeviceOrientation()
        let textAngle = textOrientation.rotationAngle

        // Calculate the angle needed to make text horizontal relative to device
        return textAngle - deviceAngle
    }

    // MARK: - Advanced Features

    /// Detect if text is skewed (not just rotated)
    func detectSkew(in image: CIImage) -> Float {
        // Simplified skew detection
        // Production would analyze text baseline angles
        return 0.0
    }

    /// Apply perspective correction using homography
    func applyPerspectiveCorrection(to image: CIImage, with info: PerspectiveInfo) -> CIImage {
        return image.transformed(by: info.transform)
    }

    /// Calculate stability score for angle correction
    func calculateStabilityScore(for orientation: TextOrientation) -> Float {
        let confidenceComponent = orientation.confidence * 0.5
        
        let areaComponent = Float(orientation.textBounds.width * orientation.textBounds.height) * 0.3
        
        // TODO: Replace with actual stability data from motion manager
        let stabilityWeight = 0.8
        let stabilityComponent = stabilityWeight * 0.2
        
        return confidenceComponent + areaComponent + Float(stabilityComponent)
    }
}
