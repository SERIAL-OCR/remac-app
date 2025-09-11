import CoreML
import Foundation

/// Core ML model definitions and metadata for the Apple Serial Scanner
/// This file defines the model specifications and provides type-safe access to model outputs
@available(iOS 13.0, *)
public struct CoreMLModelDefinitions {
    
    // MARK: - Model Names
    public static let serialRegionDetectorName = "SerialRegionDetector"
    public static let serialFormatClassifierName = "SerialFormatClassifier"
    public static let characterDisambiguatorName = "CharacterDisambiguator"
    
    // MARK: - Model Input/Output Specifications
    
    /// Serial Region Detector Model Specification
    public struct SerialRegionDetector {
        public static let inputName = "image"
        public static let inputWidth = 416
        public static let inputHeight = 416
        public static let outputBoundingBoxes = "bounding_boxes"
        public static let outputConfidences = "confidences"
        public static let outputClasses = "classes"
        
        public struct Output {
            public let boundingBoxes: [[Float]]  // [N, 4] normalized coordinates
            public let confidences: [Float]      // [N] confidence scores
            public let classes: [Int32]          // [N] class indices (0 = serial_region)
        }
    }
    
    /// Serial Format Classifier Model Specification
    public struct SerialFormatClassifier {
        public static let inputTextName = "text_features"
        public static let inputGeometryName = "geometry_features"
        public static let outputProbabilities = "probabilities"
        
        public struct Input {
            public let textFeatures: MLMultiArray    // [1, 128] text embedding
            public let geometryFeatures: MLMultiArray // [1, 8] geometry features
        }
        
        public struct Output {
            public let appleSerialProbability: Float
            public let otherTextProbability: Float
        }
    }
    
    /// Character Disambiguator Model Specification
    public struct CharacterDisambiguator {
        public static let inputName = "character_image"
        public static let inputWidth = 32
        public static let inputHeight = 32
        public static let outputProbabilities = "character_probabilities"
        
        public struct Output {
            public let characterProbabilities: [String: Float]  // character -> probability
            public let topPrediction: String
            public let confidence: Float
        }
    }
}

/// Model loading configuration and options
@available(iOS 13.0, *)
public struct MLModelConfiguration {
    
    public enum ComputeUnits: CaseIterable {
        case auto
        case cpuAndNeuralEngine
        case cpuOnly
        
        public var mlComputeUnits: MLComputeUnits {
            switch self {
            case .auto:
                return .all
            case .cpuAndNeuralEngine:
                return .cpuAndNeuralEngine
            case .cpuOnly:
                return .cpuOnly
            }
        }
        
        public var displayName: String {
            switch self {
            case .auto:
                return "Auto (Best Performance)"
            case .cpuAndNeuralEngine:
                return "CPU + Neural Engine"
            case .cpuOnly:
                return "CPU Only"
            }
        }
    }
    
    public let computeUnits: ComputeUnits
    public let preferredMetalDevice: MTLDevice?
    public let parameters: [MLParameterKey: Any]
    
    public init(computeUnits: ComputeUnits = .auto,
                preferredMetalDevice: MTLDevice? = nil,
                parameters: [MLParameterKey: Any] = [:]) {
        self.computeUnits = computeUnits
        self.preferredMetalDevice = preferredMetalDevice
        self.parameters = parameters
    }
    
    public var mlConfiguration: CoreML.MLModelConfiguration {
        let config = CoreML.MLModelConfiguration()
        // Set compute units using our enum's conversion method
        config.computeUnits = self.computeUnits.mlComputeUnits
        // Set Metal device if provided
        if let metalDevice = self.preferredMetalDevice {
            config.preferredMetalDevice = metalDevice
        }
        // Set any additional parameters
        if !parameters.isEmpty {
            config.parameters = parameters
        }
        return config
    }
}

/// Model loading errors
public enum MLModelError: Error, LocalizedError {
    case modelNotFound(String)
    case loadingFailed(String, Error)
    case invalidInput(String)
    case predictionFailed(String, Error)
    case unsupportedDevice
    
    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "Core ML model '\(name)' not found in bundle"
        case .loadingFailed(let name, let error):
            return "Failed to load model '\(name)': \(error.localizedDescription)"
        case .invalidInput(let message):
            return "Invalid model input: \(message)"
        case .predictionFailed(let name, let error):
            return "Prediction failed for model '\(name)': \(error.localizedDescription)"
        case .unsupportedDevice:
            return "Core ML is not supported on this device"
        }
    }
}
