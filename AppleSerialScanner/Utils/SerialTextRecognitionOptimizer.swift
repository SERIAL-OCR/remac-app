import Vision
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Specialized Vision configuration for Apple serial number recognition
struct SerialTextRecognitionOptimizer {
    
    /// Configure a VNRecognizeTextRequest for optimal Apple serial number recognition
    /// - Parameters:
    ///   - request: The text recognition request to optimize
    ///   - isIPad: Whether the device is an iPad (for device-specific optimizations)
    static func optimizeForSerialNumbers(_ request: VNRecognizeTextRequest, isIPad: Bool = false) {
        // Use accurate recognition for serial numbers
        request.recognitionLevel = .accurate
        
        // Serial numbers don't need language correction
        request.usesLanguageCorrection = false
        
        // Use English only for serial numbers
        request.recognitionLanguages = ["en-US"]
        
        // Set minimum text height - smaller for iPad's higher resolution camera
        request.minimumTextHeight = isIPad ? 0.02 : 0.05
        
        // Set revision to latest for best results
        request.revision = VNRecognizeTextRequestRevision2
        
        // Add custom words for common Apple serial number patterns
        request.customWords = [
            // Common prefixes for Apple serial numbers
            "C02", "FVFG", "FVFC", "FVFD", "FVFF", "FVFH", "FVFJ", "FVFK", "FVFL", "FVFM", "FVFN", "FVFP",
            "FVFQ", "FVFR", "FVFT", "FVFV", "FVFW", "FVFY", "FVG0", "FVG1", "FVG2", "FVG3", "FVG4", "C32",
            "C39", "C3G", "C3T", "C3V", "C3X", "C4W", "F9F", "F9G", "F9H", "F9J", "F9K", "F9L", "F9M", "F9N",
            "DKQ", "DKR", "DKT", "DKV", "DKW", "DKX", "DKY", "DL0", "DL1", "DL2", "DL3", "DL4", "G0L", "G0M",
            "G0N", "G0P"
        ]
    }
    
    /// Process recognized text for potential Apple serial numbers
    /// - Parameters:
    ///   - text: The recognized text
    ///   - confidence: The confidence level from Vision
    /// - Returns: Processed text with common OCR errors corrected
    static func processRecognizedSerialText(_ text: String, confidence: Float) -> (text: String, confidence: Float) {
        // Clean the text
        var processedText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        
        // Correct common OCR errors in serial numbers
        let corrections: [String: String] = [
            "O": "0",  // Letter O to number 0
            "I": "1",  // Letter I to number 1
            "S": "5",  // Letter S to number 5
            "B": "8",  // Letter B to number 8
            "Z": "2",  // Letter Z to number 2
            "D": "0",  // Sometimes D is misread as 0
            "Q": "0",  // Letter Q to number 0
            " ": "",   // Remove spaces
            "-": "",   // Remove hyphens
            ".": "",   // Remove periods
            ",": ""    // Remove commas
        ]
        
        for (incorrect, correct) in corrections {
            processedText = processedText.replacingOccurrences(of: incorrect, with: correct)
        }
        
        // Boost confidence for certain patterns that are likely to be serial numbers
        var adjustedConfidence = confidence
        
        // Boost confidence if the text is the right length for an Apple serial
        if processedText.count == 12 {
            adjustedConfidence += 0.05
        }
        
        // Boost confidence for texts starting with common Apple serial prefixes
        let commonPrefixes = ["C02", "C39", "C3T", "F9F", "G0", "DKQ", "FVF"]
        for prefix in commonPrefixes {
            if processedText.hasPrefix(prefix) {
                adjustedConfidence += 0.1
                break
            }
        }
        
        // Cap confidence at 1.0
        adjustedConfidence = min(adjustedConfidence, 1.0)
        
        return (processedText, adjustedConfidence)
    }
}
