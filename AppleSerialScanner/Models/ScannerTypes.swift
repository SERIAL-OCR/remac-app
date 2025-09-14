import Foundation

/// Phase 1: Scanner implementation types for VisionKit integration
enum ScannerType {
    case visionKit  // iOS 16+ VisionKit DataScannerViewController
    case legacy     // Custom AVFoundation implementation
}

/// Phase 1: Scanner configuration for different implementations
struct ScannerConfiguration {
    let type: ScannerType
    let isHighlightingEnabled: Bool
    let isGuidanceEnabled: Bool
    let qualityLevel: ScannerQualityLevel
    let recognizesMultipleItems: Bool
    
    static let visionKitDefault = ScannerConfiguration(
        type: .visionKit,
        isHighlightingEnabled: true,
        isGuidanceEnabled: true,
        qualityLevel: .balanced,
        recognizesMultipleItems: true
    )
    
    static let legacyDefault = ScannerConfiguration(
        type: .legacy,
        isHighlightingEnabled: false,
        isGuidanceEnabled: false,
        qualityLevel: .balanced,
        recognizesMultipleItems: false
    )
}

/// Quality levels for scanner performance tuning
enum ScannerQualityLevel {
    case fast      // Prioritize speed over accuracy
    case balanced  // Balance between speed and accuracy
    case accurate  // Prioritize accuracy over speed
}