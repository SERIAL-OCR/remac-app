import CoreML
import Foundation
import UIKit
import Vision

/// Example usage and integration code for the ML models
/// This file demonstrates how to use all 3 ML models in your Xcode project
@available(iOS 13.0, *)
public class MLModelUsageExample {
    
    private let modelManager = MLModelManager.shared
    
    // MARK: - Complete Serial Number Detection Pipeline
    
    /// Complete pipeline to detect and extract Apple serial numbers from an image
    /// - Parameter image: Input image containing potential serial numbers
    /// - Returns: Array of detected and validated Apple serial numbers
    public func detectAppleSerialNumbers(in image: UIImage) async throws -> [DetectedSerialNumber] {
        var detectedSerials: [DetectedSerialNumber] = []
        
        // Step 1: Detect serial regions using SerialRegionDetector
        let regions = try await modelManager.detectSerialRegions(in: image)
        
        for region in regions {
            // Step 2: Extract text from the region using Vision framework
            let extractedText = try await extractTextFromRegion(region, in: image)
            
            // Step 3: Classify if the text is an Apple serial using SerialFormatClassifier
            let classification = try await classifyTextAsAppleSerial(extractedText)
            
            if classification.isAppleSerial {
                // Step 4: Disambiguate individual characters using CharacterDisambiguator
                let disambiguatedText = try await disambiguateCharacters(extractedText, in: region, image: image)
                
                let detectedSerial = DetectedSerialNumber(
                    text: disambiguatedText,
                    boundingBox: region.boundingBox,
                    confidence: region.confidence * classification.appleSerialProbability,
                    region: region
                )
                detectedSerials.append(detectedSerial)
            }
        }
        
        return detectedSerials
    }
    
    // MARK: - Individual Model Usage Examples
    
    /// Example: Using SerialRegionDetector to find potential serial number locations
    public func findSerialRegions(in image: UIImage) async throws -> [SerialRegion] {
        return try await modelManager.detectSerialRegions(in: image)
    }
    
    /// Example: Using SerialFormatClassifier to validate if text is an Apple serial
    public func validateAppleSerial(_ text: String) async throws -> SerialFormatClassification {
        // Extract text features (this would typically use a text embedding model)
        let textFeatures = extractTextFeatures(from: text)
        
        // Extract geometry features (aspect ratio, position, etc.)
        let geometryFeatures = extractGeometryFeatures(from: text)
        
        return try await modelManager.classifySerialFormat(
            textFeatures: textFeatures,
            geometryFeatures: geometryFeatures
        )
    }
    
    /// Example: Using CharacterDisambiguator to improve OCR accuracy
    public func improveOCRAccuracy(for characterImage: UIImage) async throws -> CharacterPrediction {
        return try await modelManager.disambiguateCharacter(characterImage)
    }
    
    // MARK: - Helper Methods
    
    private func extractTextFromRegion(_ region: SerialRegion, in image: UIImage) async throws -> String {
        // This would typically use Vision framework's VNRecognizeTextRequest
        // For this example, we'll return a mock implementation
        
        let request = VNRecognizeTextRequest { request, error in
            // Handle text recognition results
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cgImage: image.cgImage!, options: [:])
        try handler.perform([request])
        
        // Extract text from the specific region
        // This is a simplified version - in practice you'd crop the region first
        return "MOCK_SERIAL_TEXT" // Replace with actual OCR result
    }
    
    private func classifyTextAsAppleSerial(_ text: String) async throws -> SerialFormatClassification {
        let textFeatures = extractTextFeatures(from: text)
        let geometryFeatures = extractGeometryFeatures(from: text)
        
        return try await modelManager.classifySerialFormat(
            textFeatures: textFeatures,
            geometryFeatures: geometryFeatures
        )
    }
    
    private func disambiguateCharacters(_ text: String, in region: SerialRegion, image: UIImage) async throws -> String {
        var disambiguatedText = ""
        
        // For each character in the text, use the CharacterDisambiguator
        for (index, character) in text.enumerated() {
            // Extract character image from the region
            let characterImage = extractCharacterImage(at: index, from: region, in: image)
            
            // Use CharacterDisambiguator to get the best prediction
            let prediction = try await modelManager.disambiguateCharacter(characterImage)
            disambiguatedText += prediction.topPrediction
        }
        
        return disambiguatedText
    }
    
    // MARK: - Feature Extraction Helpers
    
    private func extractTextFeatures(from text: String) -> [Float] {
        // Mock implementation - in practice you'd use a text embedding model
        // This should return a 128-dimensional feature vector
        return Array(repeating: 0.0, count: 128).map { Float($0) }
    }
    
    private func extractGeometryFeatures(from text: String) -> [Float] {
        // Mock implementation - extract geometry features like:
        // - Text length
        // - Aspect ratio
        // - Position in image
        // - Font characteristics
        // This should return an 8-dimensional feature vector
        return [
            Float(text.count),           // Length
            1.0,                         // Aspect ratio
            0.5,                         // X position (normalized)
            0.5,                         // Y position (normalized)
            0.8,                         // Font size estimate
            0.0,                         // Rotation angle
            0.0,                         // Skew
            1.0                          // Confidence
        ]
    }
    
    private func extractCharacterImage(at index: Int, from region: SerialRegion, in image: UIImage) -> UIImage {
        // Mock implementation - in practice you'd:
        // 1. Crop the character from the region
        // 2. Resize to 32x32
        // 3. Apply preprocessing (normalization, etc.)
        
        // For now, return a mock 32x32 image
        let size = CGSize(width: 32, height: 32)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }
}

// MARK: - Data Models for Complete Pipeline

@available(iOS 13.0, *)
public struct DetectedSerialNumber {
    public let text: String
    public let boundingBox: CGRect
    public let confidence: Float
    public let region: SerialRegion
}

// MARK: - SwiftUI Integration Example

import SwiftUI

@available(iOS 13.0, *)
struct MLModelIntegrationView: View {
    @StateObject private var modelManager = MLModelManager.shared
    @State private var detectedSerials: [DetectedSerialNumber] = []
    @State private var isProcessing = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack {
            if modelManager.isInitialized {
                Text("ML Models Loaded Successfully")
                    .foregroundColor(.green)
            } else if let error = modelManager.initializationError {
                Text("Model Loading Error: \(error)")
                    .foregroundColor(.red)
            } else {
                Text("Loading ML Models...")
                    .foregroundColor(.orange)
            }
            
            if isProcessing {
                ProgressView("Processing Image...")
            }
            
            if !detectedSerials.isEmpty {
                List(detectedSerials, id: \.text) { serial in
                    VStack(alignment: .leading) {
                        Text("Serial: \(serial.text)")
                            .font(.headline)
                        Text("Confidence: \(serial.confidence, specifier: "%.2f")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if let error = errorMessage {
                Text("Error: \(error)")
                    .foregroundColor(.red)
            }
        }
        .onAppear {
            // Models are automatically initialized in MLModelManager
        }
    }
    
    func processImage(_ image: UIImage) {
        isProcessing = true
        errorMessage = nil
        
        Task {
            do {
                let usageExample = MLModelUsageExample()
                let serials = try await usageExample.detectAppleSerialNumbers(in: image)
                
                await MainActor.run {
                    self.detectedSerials = serials
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isProcessing = false
                }
            }
        }
    }
}

// MARK: - Model Configuration Examples

@available(iOS 13.0, *)
public class MLModelConfigurationExamples {
    
    /// Example: Configure models for maximum performance
    public static func configureForPerformance() -> MLModelConfiguration {
        return MLModelConfiguration(
            computeUnits: .cpuAndNeuralEngine,
            parameters: [
                MLParameterKey.computeUnits: MLComputeUnits.cpuAndNeuralEngine
            ]
        )
    }
    
    /// Example: Configure models for maximum accuracy
    public static func configureForAccuracy() -> MLModelConfiguration {
        return MLModelConfiguration(
            computeUnits: .auto,
            parameters: [
                MLParameterKey.computeUnits: MLComputeUnits.all
            ]
        )
    }
    
    /// Example: Configure models for CPU-only execution
    public static func configureForCPUOnly() -> MLModelConfiguration {
        return MLModelConfiguration(
            computeUnits: .cpuOnly,
            parameters: [
                MLParameterKey.computeUnits: MLComputeUnits.cpuOnly
            ]
        )
    }
}

// MARK: - Error Handling Examples

@available(iOS 13.0, *)
public class MLErrorHandlingExamples {
    
    /// Example: Comprehensive error handling for model operations
    public static func handleModelError(_ error: Error) -> String {
        if let mlError = error as? MLModelError {
            switch mlError {
            case .modelNotFound(let name):
                return "Model '\(name)' not found. Please ensure the model file is included in the app bundle."
            case .loadingFailed(let name, let underlyingError):
                return "Failed to load model '\(name)': \(underlyingError.localizedDescription)"
            case .invalidInput(let message):
                return "Invalid input: \(message)"
            case .predictionFailed(let name, let underlyingError):
                return "Prediction failed for '\(name)': \(underlyingError.localizedDescription)"
            case .unsupportedDevice:
                return "Core ML is not supported on this device."
            }
        } else {
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}