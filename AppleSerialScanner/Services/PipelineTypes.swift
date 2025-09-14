import Foundation
import CoreImage
import os.log

// MARK: - Scanning Modes
enum ScanningMode: String, CaseIterable {
    case screen = "screen"
    case chassis = "chassis"
    case auto = "auto"
    
    var description: String {
        switch self {
        case .screen: return "Screen Mode"
        case .chassis: return "Chassis Mode"
        case .auto: return "Auto Mode"
        }
    }
}

// MARK: - Surface Types
enum SurfaceType: String, Codable {
    case metal      // Reflective, etched/engraved serials (MacBooks, iPads)
    case plastic    // Smooth, printed/molded serials (chargers, cases)
    case glass      // Transparent surfaces (screen protectors, displays)
    case screen     // Digital displays (device screens, monitors)
    case chassis    // Device chassis/body
    case paper      // Printed labels, documentation
    case unknown    // Cannot determine surface type

    /// Human-readable description for UI display
    var description: String {
        switch self {
        case .metal: return "Metal Surface"
        case .plastic: return "Plastic Surface"
        case .glass: return "Glass Surface"
        case .screen: return "Screen Display"
        case .chassis: return "Chassis/Body"
        case .paper: return "Paper Label"
        case .unknown: return "Unknown Surface"
        }
    }
}

// MARK: - Pipeline Result Types
enum PipelineResult {
    case success(
        screenDetection: ScreenDetectionResult,
        surfaceClassification: SurfaceClassificationResult,
        preprocessing: PreprocessingResult,
        fastOCR: FastOCRResult,
        resolvedCandidates: [ResolvedCandidate],
        validation: ValidationResult,
        stability: StabilityResult,
        accurateOCR: AccurateOCRResult?,
        totalProcessingTime: TimeInterval
    )
    case noScreenDetected(processingTime: TimeInterval)
    case busy
    case error(Error, processingTime: TimeInterval)
    
    static func busy() -> PipelineResult {
        return .busy
    }
}

// MARK: - Processing Metrics
class ProcessingMetrics: ObservableObject {
    @Published var averageFrameTime: TimeInterval = 0
    @Published var minFrameTime: TimeInterval = 0
    @Published var maxFrameTime: TimeInterval = 0
    @Published var totalFramesProcessed: Int = 0
    @Published var framesPerSecond: Double = 0
    
    private var frameTimes: [TimeInterval] = []
    private let maxFrameHistory = 30
    
    func addFrameTime(_ time: TimeInterval) {
        frameTimes.append(time)
        
        if frameTimes.count > maxFrameHistory {
            frameTimes.removeFirst()
        }
        
        totalFramesProcessed += 1
        updateMetrics()
    }
    
    private func updateMetrics() {
        guard !frameTimes.isEmpty else { return }
        
        averageFrameTime = frameTimes.reduce(0, +) / Double(frameTimes.count)
        minFrameTime = frameTimes.min() ?? 0
        maxFrameTime = frameTimes.max() ?? 0
        framesPerSecond = 1.0 / averageFrameTime
    }
    
    func reset() {
        frameTimes.removeAll()
        totalFramesProcessed = 0
        averageFrameTime = 0
        minFrameTime = 0
        maxFrameTime = 0
        framesPerSecond = 0
    }
}

// MARK: - Processing Details
struct ProcessingDetails {
    let screenDetection: ScreenDetectionResult
    let surfaceType: SurfaceType
    let ocrAttempts: Int
    let ambiguityResolutions: Int
    let totalProcessingTime: TimeInterval
}

// MARK: - Pipeline Analytics
struct PipelineAnalytics {
    let overallHealthScore: Float
    let screenDetectionAccuracy: Float
    let ocrPerformance: OCRPerformanceMetrics
    let stabilityMetrics: StabilityMetrics
    let processingTimes: ProcessingTimeMetrics
}

struct OCRPerformanceMetrics {
    let fastPassSuccessRate: Float
    let accuratePassSuccessRate: Float
    let averageConfidence: Float
    let characterCorrections: Int
}

struct StabilityMetrics {
    let averageStabilityScore: Float
    let lockSuccessRate: Float
    let averageFramesToLock: Int
}

struct ProcessingTimeMetrics {
    let averageScreenDetection: TimeInterval
    let averageOCR: TimeInterval
    let averageValidation: TimeInterval
    let averageTotal: TimeInterval
}

// MARK: - Preprocessing Result
struct PreprocessingResult {
    let processedImages: [ProcessedImage]
    let appliedFilters: [String]
    let processingTime: TimeInterval
}

// MARK: - Processed Image
struct ProcessedImage {
    let image: CIImage
    let isInverted: Bool
    let processingMethod: String
    let metadata: [String: Any]
    
    init(image: CIImage, isInverted: Bool, processingMethod: String, metadata: [String: Any] = [:]) {
        self.image = image
        self.isInverted = isInverted
        self.processingMethod = processingMethod
        self.metadata = metadata
    }
}

// MARK: - Text Candidate
struct TextCandidate {
    let text: String
    let confidence: Float
    let boundingBox: CGRect
    let ocrSource: OCRSource
    let timestamp: Date
    let imageIndex: Int
    let isInverted: Bool
    let alternativeRank: Int
    let observationIndex: Int
    
    enum OCRSource {
        case fast
        case accurate
    }
    
    init(text: String, confidence: Float, boundingBox: CGRect, source: OCRSource, imageIndex: Int = 0, isInverted: Bool = false, alternativeRank: Int = 0, observationIndex: Int = 0) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.ocrSource = source
        self.timestamp = Date()
        self.imageIndex = imageIndex
        self.isInverted = isInverted
        self.alternativeRank = alternativeRank
        self.observationIndex = observationIndex
    }
}

// MARK: - Fast OCR Result
struct FastOCRResult {
    let textCandidates: [TextCandidate]
    let processingTime: TimeInterval
    let skippedDueToThrottling: Bool
}

// MARK: - Accurate OCR Result
struct AccurateOCRResult {
    let textCandidates: [TextCandidate]
    let processingTime: TimeInterval
    let error: Error?
}

// MARK: - Screen Detection Result
struct ScreenDetectionResult {
    let isScreenDetected: Bool
    let roi: CGRect
    let confidence: Float
    let processingTime: TimeInterval
}

// MARK: - Resolved Candidate
struct ResolvedCandidate {
    let originalCandidate: TextCandidate
    let resolvedText: String
    let adjustedConfidence: Float
    let hasAdjustments: Bool
    let corrections: [String]
}

// MARK: - Validation Result
struct ValidationResult {
    let bestCandidate: ValidatedCandidate?
    let allValidCandidates: [ValidatedCandidate]
    let rejectedCandidates: [RejectedCandidate]
}

// MARK: - Validated Candidate
struct ValidatedCandidate {
    let candidate: TextCandidate
    let validation: SerialValidationResult
    let compositeScore: Float
}

// MARK: - Rejected Candidate
struct RejectedCandidate {
    let candidate: TextCandidate
    let validation: SerialValidationResult
}

// MARK: - Serial Validation Result
struct SerialValidationResult {
    let isValid: Bool
    let cleanedSerial: String
    let rejectionReason: RejectionReason?
    let confidence: Float
}

enum RejectionReason {
    case invalidLength(Int)
    case invalidCharacters([Character])
    case patternMismatch
    
    var description: String {
        switch self {
        case .invalidLength(let length):
            return "Invalid length: \(length) (expected 10-12 characters)"
        case .invalidCharacters(let chars):
            return "Invalid characters: \(chars.map(String.init).joined(separator: ", "))"
        case .patternMismatch:
            return "Does not match Apple serial pattern"
        }
    }
}

// MARK: - Stability Result
struct StabilityResult {
    let state: StabilityState
    let stableCandidate: String?
    let guidanceMessage: String
    let shouldLock: Bool
    let confidence: Float
}

enum StabilityState {
    case seeking
    case candidate
    case stabilized
    case locked
}

// MARK: - Surface Classification Result
struct SurfaceClassificationResult {
    let surfaceType: SurfaceType
    let confidence: Float
    let polarityRecommendation: PolarityRecommendation
    let processingTime: TimeInterval
    let characteristics: ImageCharacteristics
    let preprocessingRecommendations: PreprocessingRecommendations
}

// MARK: - Polarity Recommendation
struct PolarityRecommendation {
    let primary: PolarityHint
    let shouldTestBoth: Bool
    
    enum PolarityHint {
        case normal    // Dark text on light background
        case inverted  // Light text on dark background
        case both      // Try both polarities
    }
}

// MARK: - Image Characteristics
public struct ImageCharacteristics {
    let histogram: [Float]
    let edgeDensity: Float
    let localContrast: Float
    let brightness: Float
    let contrastSpread: Float
    let confidence: Float
}

// MARK: - Preprocessing Recommendations
struct PreprocessingRecommendations {
    let brightnessAdjustment: Float
    let contrastAdjustment: Float
    let claheEnabled: Bool
    let noiseReduction: Bool
    let sharpenIntensity: Float
}
