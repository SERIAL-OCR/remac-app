# ML Model Integration Guide for Apple Serial Scanner

This guide provides complete instructions for integrating the 3 ML models into your Xcode project.

## Models Overview

1. **SerialRegionDetector.mlmodel** - Detects potential serial number regions in images
2. **SerialFormatClassifier.mlmodel** - Classifies whether detected text is an Apple serial number
3. **CharacterDisambiguator.mlmodel** - Disambiguates individual characters for improved OCR accuracy

## Step 1: Add Model Files to Xcode

1. Open your Xcode project
2. Right-click on your project navigator
3. Select "Add Files to [ProjectName]"
4. Navigate to your project directory and select these files:
   - `CharacterDisambiguator.mlmodel`
   - `SerialFormatClassifier.mlmodel`
   - `SerialRegionDetector.mlmodel`
5. Ensure "Add to target" is checked for your main app target
6. Click "Add"

## Step 2: Add Required Swift Files

Add these Swift files to your project:

1. **CoreMLModelDefinitions.swift** (already exists)
2. **MLModelManager.swift** (new)
3. **MLModelUsageExample.swift** (new)

## Step 3: Import Required Frameworks

In your main app file or any file using the ML models, add these imports:

```swift
import CoreML
import Foundation
import UIKit
import Vision
```

## Step 4: Basic Usage

### Initialize the Model Manager

```swift
@available(iOS 13.0, *)
class YourViewController: UIViewController {
    private let modelManager = MLModelManager.shared
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Models are automatically initialized
        // Check initialization status
        if modelManager.isInitialized {
            print("ML Models loaded successfully")
        } else if let error = modelManager.initializationError {
            print("Model loading error: \(error)")
        }
    }
}
```

### Detect Serial Numbers in an Image

```swift
@available(iOS 13.0, *)
func detectSerialNumbers(in image: UIImage) {
    Task {
        do {
            let usageExample = MLModelUsageExample()
            let detectedSerials = try await usageExample.detectAppleSerialNumbers(in: image)
            
            await MainActor.run {
                // Update UI with detected serials
                for serial in detectedSerials {
                    print("Found serial: \(serial.text) with confidence: \(serial.confidence)")
                }
            }
        } catch {
            print("Detection failed: \(error.localizedDescription)")
        }
    }
}
```

## Step 5: SwiftUI Integration

### Create a SwiftUI View

```swift
import SwiftUI

@available(iOS 13.0, *)
struct SerialScannerView: View {
    @StateObject private var modelManager = MLModelManager.shared
    @State private var detectedSerials: [DetectedSerialNumber] = []
    @State private var selectedImage: UIImage?
    
    var body: some View {
        VStack {
            if modelManager.isInitialized {
                Text("ML Models Ready")
                    .foregroundColor(.green)
            } else {
                Text("Loading Models...")
                    .foregroundColor(.orange)
            }
            
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                
                Button("Detect Serial Numbers") {
                    detectSerialNumbers(in: image)
                }
                .disabled(!modelManager.isInitialized)
            }
            
            List(detectedSerials, id: \.text) { serial in
                VStack(alignment: .leading) {
                    Text(serial.text)
                        .font(.headline)
                    Text("Confidence: \(serial.confidence, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func detectSerialNumbers(in image: UIImage) {
        Task {
            do {
                let usageExample = MLModelUsageExample()
                let serials = try await usageExample.detectAppleSerialNumbers(in: image)
                
                await MainActor.run {
                    self.detectedSerials = serials
                }
            } catch {
                print("Detection failed: \(error.localizedDescription)")
            }
        }
    }
}
```

## Step 6: Advanced Configuration

### Configure for Performance

```swift
@available(iOS 13.0, *)
let performanceConfig = MLModelConfigurationExamples.configureForPerformance()
```

### Configure for Accuracy

```swift
@available(iOS 13.0, *)
let accuracyConfig = MLModelConfigurationExamples.configureForAccuracy()
```

### Configure for CPU Only

```swift
@available(iOS 13.0, *)
let cpuOnlyConfig = MLModelConfigurationExamples.configureForCPUOnly()
```

## Step 7: Individual Model Usage

### Using SerialRegionDetector

```swift
@available(iOS 13.0, *)
func findSerialRegions(in image: UIImage) async throws -> [SerialRegion] {
    return try await MLModelManager.shared.detectSerialRegions(in: image)
}
```

### Using SerialFormatClassifier

```swift
@available(iOS 13.0, *)
func validateAppleSerial(_ text: String) async throws -> SerialFormatClassification {
    let textFeatures = extractTextFeatures(from: text) // Your implementation
    let geometryFeatures = extractGeometryFeatures(from: text) // Your implementation
    
    return try await MLModelManager.shared.classifySerialFormat(
        textFeatures: textFeatures,
        geometryFeatures: geometryFeatures
    )
}
```

### Using CharacterDisambiguator

```swift
@available(iOS 13.0, *)
func improveOCRAccuracy(for characterImage: UIImage) async throws -> CharacterPrediction {
    return try await MLModelManager.shared.disambiguateCharacter(characterImage)
}
```

## Step 8: Error Handling

### Comprehensive Error Handling

```swift
@available(iOS 13.0, *)
func handleMLModelError(_ error: Error) {
    let errorMessage = MLErrorHandlingExamples.handleModelError(error)
    print("ML Model Error: \(errorMessage)")
    
    // Show user-friendly error message
    DispatchQueue.main.async {
        // Update UI with error message
    }
}
```

## Step 9: Testing

### Test Model Loading

```swift
@available(iOS 13.0, *)
func testModelLoading() {
    let modelManager = MLModelManager.shared
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
        if modelManager.isInitialized {
            print("✅ All models loaded successfully")
        } else {
            print("❌ Model loading failed: \(modelManager.initializationError ?? "Unknown error")")
        }
    }
}
```

### Test Individual Models

```swift
@available(iOS 13.0, *)
func testIndividualModels() async {
    // Test with a sample image
    guard let sampleImage = UIImage(named: "sample_serial_image") else {
        print("Sample image not found")
        return
    }
    
    do {
        // Test SerialRegionDetector
        let regions = try await MLModelManager.shared.detectSerialRegions(in: sampleImage)
        print("Found \(regions.count) potential serial regions")
        
        // Test CharacterDisambiguator with a character image
        if let characterImage = UIImage(named: "sample_character") {
            let prediction = try await MLModelManager.shared.disambiguateCharacter(characterImage)
            print("Character prediction: \(prediction.topPrediction) with confidence: \(prediction.confidence)")
        }
        
    } catch {
        print("Testing failed: \(error.localizedDescription)")
    }
}
```

## Step 10: Performance Optimization

### Memory Management

```swift
@available(iOS 13.0, *)
class OptimizedMLManager {
    private let modelManager = MLModelManager.shared
    
    func processImageEfficiently(_ image: UIImage) async throws -> [DetectedSerialNumber] {
        // Resize image to optimal size before processing
        let resizedImage = image.resized(to: CGSize(width: 416, height: 416))
        
        // Process in background queue
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    let usageExample = MLModelUsageExample()
                    let result = try await usageExample.detectAppleSerialNumbers(in: resizedImage)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
```

### Batch Processing

```swift
@available(iOS 13.0, *)
func processMultipleImages(_ images: [UIImage]) async throws -> [[DetectedSerialNumber]] {
    return try await withThrowingTaskGroup(of: [DetectedSerialNumber].self) { group in
        for image in images {
            group.addTask {
                let usageExample = MLModelUsageExample()
                return try await usageExample.detectAppleSerialNumbers(in: image)
            }
        }
        
        var results: [[DetectedSerialNumber]] = []
        for try await result in group {
            results.append(result)
        }
        return results
    }
}
```

## Troubleshooting

### Common Issues

1. **Model not found**: Ensure model files are added to the app bundle
2. **Loading failed**: Check device compatibility and available memory
3. **Prediction failed**: Verify input image format and size
4. **Performance issues**: Use appropriate compute units configuration

### Debug Information

```swift
@available(iOS 13.0, *)
func printDebugInfo() {
    let modelManager = MLModelManager.shared
    print("Model Manager Status:")
    print("- Initialized: \(modelManager.isInitialized)")
    print("- Error: \(modelManager.initializationError ?? "None")")
    
    // Check device capabilities
    if #available(iOS 13.0, *) {
        print("Core ML Available: \(MLModel.availableComputeDevices)")
    }
}
```

## Requirements

- iOS 13.0+
- Xcode 12.0+
- Core ML framework
- Vision framework (for text recognition)

## File Structure

```
YourProject/
├── Models/
│   └── ML/
│       ├── CoreMLModelDefinitions.swift
│       ├── MLModelManager.swift
│       ├── MLModelUsageExample.swift
│       └── MLModelSetupGuide.md
├── CharacterDisambiguator.mlmodel
├── SerialFormatClassifier.mlmodel
└── SerialRegionDetector.mlmodel
```

This setup provides a complete, production-ready ML model integration for your Apple Serial Scanner app.