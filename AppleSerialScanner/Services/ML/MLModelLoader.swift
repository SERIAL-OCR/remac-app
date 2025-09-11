import CoreML
import Foundation
import os.log

/// Centralized loader for all Core ML models with lazy loading and warmup capabilities
@available(iOS 13.0, *)
@MainActor
public final class MLModelLoader: ObservableObject {
    
    // MARK: - Singleton
    public static let shared = MLModelLoader()
    
    // MARK: - Private Properties
    private var loadedModels: [String: MLModel] = [:]
    private var loadingTasks: [String: Task<MLModel, Error>] = [:]
    private let logger = Logger(subsystem: "AppleSerialScanner", category: "MLModelLoader")
    
    // MARK: - Configuration
    @Published public var configuration = MLModelConfiguration()
    @Published public var isWarmupComplete = false
    @Published public var loadingProgress: [String: Bool] = [:]
    
    private init() {
        setupInitialConfiguration()
    }
    
    // MARK: - Public Interface
    
    /// Load all models asynchronously with warmup
    public func loadAllModels() async throws {
        logger.info("Starting to load all Core ML models")
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Load Serial Region Detector
            group.addTask {
                do {
                    _ = try await self.loadSerialRegionDetector()
                } catch {
                    throw error
                }
            }
            
            // Load Serial Format Classifier
            group.addTask {
                do {
                    _ = try await self.loadSerialFormatClassifier()
                } catch {
                    throw error
                }
            }
            
            // Load Character Disambiguator
            group.addTask {
                do {
                    _ = try await self.loadCharacterDisambiguator()
                } catch {
                    throw error
                }
            }
            
            // Wait for all models to load
            do {
                for try await _ in group {
                    // Models loaded successfully
                }
            } catch {
                logger.error("Failed to load models: \(error.localizedDescription)")
                throw error
            }
        }
        
        // Perform warmup
        try await performWarmup()
        await MainActor.run {
            self.isWarmupComplete = true
        }
        
        logger.info("All Core ML models loaded and warmed up successfully")
    }
    
    /// Load Serial Region Detector model
    public func loadSerialRegionDetector() async throws -> MLModel {
        return try await loadModel(
            name: CoreMLModelDefinitions.serialRegionDetectorName,
            bundleName: "SerialRegionDetector"
        )
    }
    
    /// Load Serial Format Classifier model
    public func loadSerialFormatClassifier() async throws -> MLModel {
        return try await loadModel(
            name: CoreMLModelDefinitions.serialFormatClassifierName,
            bundleName: "SerialFormatClassifier"
        )
    }
    
    /// Load Character Disambiguator model
    public func loadCharacterDisambiguator() async throws -> MLModel {
        return try await loadModel(
            name: CoreMLModelDefinitions.characterDisambiguatorName,
            bundleName: "CharacterDisambiguator"
        )
    }
    
    /// Get already loaded model (returns nil if not loaded)
    public func getLoadedModel(_ name: String) -> MLModel? {
        return loadedModels[name]
    }
    
    /// Update model configuration and reload if necessary
    public func updateConfiguration(_ newConfig: MLModelConfiguration) async throws {
        guard newConfig.computeUnits != configuration.computeUnits else {
            return // No change needed
        }
        
        logger.info("Updating ML model configuration")
        await MainActor.run {
            self.configuration = newConfig
            self.isWarmupComplete = false
        }
        
        // Clear loaded models to force reload with new configuration
        loadedModels.removeAll()
        loadingTasks.removeAll()
        
        // Reload all models
        try await loadAllModels()
    }
    
    // MARK: - Private Methods
    
    private func setupInitialConfiguration() {
        // Set default configuration based on device capabilities
        if ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil {
            // Running in simulator - use CPU only
            configuration = MLModelConfiguration(computeUnits: .cpuOnly)
        } else {
            // Real device - use auto selection
            configuration = MLModelConfiguration(computeUnits: .auto)
        }
    }
    
    private func loadModel(name: String, bundleName: String) async throws -> MLModel {
        // Check if already loaded
        if let existingModel = loadedModels[name] {
            return existingModel
        }
        
        // Check if loading is in progress
        if let existingTask = loadingTasks[name] {
            return try await existingTask.value
        }
        
        // Start loading
        let loadingTask = Task<MLModel, Error> {
            try await self.performModelLoad(name: name, bundleName: bundleName)
        }
        
        loadingTasks[name] = loadingTask
        
        do {
            let model = try await loadingTask.value
            loadedModels[name] = model
            loadingTasks.removeValue(forKey: name)
            
            await MainActor.run {
                self.loadingProgress[name] = true
            }
            
            return model
        } catch {
            loadingTasks.removeValue(forKey: name)
            await MainActor.run {
                self.loadingProgress[name] = false
            }
            throw error
        }
    }
    
    private func performModelLoad(name: String, bundleName: String) async throws -> MLModel {
        logger.info("Loading Core ML model: \(name)")
        
        // Try to load .mlpackage first, then fallback to .mlmodel
        let model: MLModel
        
        // Use the bridged CoreML configuration produced by our custom configuration
        let coreMLConfig = configuration.mlConfiguration
        
        // Now use the native CoreML configuration
        if let packageURL = Bundle.main.url(forResource: bundleName, withExtension: "mlpackage") {
            logger.info("Loading \(name) from .mlpackage")
            model = try MLModel(contentsOf: packageURL, configuration: coreMLConfig)
        } else if let modelURL = Bundle.main.url(forResource: bundleName, withExtension: "mlmodel") {
            logger.info("Loading \(name) from .mlmodel (fallback)")
            model = try MLModel(contentsOf: modelURL, configuration: coreMLConfig)
        } else {
            logger.error("Model \(name) not found in bundle")
            throw MLModelError.modelNotFound(name)
        }
        
        logger.info("Successfully loaded model: \(name)")
        return model
    }
    
    private func performWarmup() async throws {
        logger.info("Starting Core ML model warmup")
        
        // Create dummy inputs for warmup
        let dummyImage = createDummyPixelBuffer(width: 416, height: 416)
        
        // Warmup all loaded models
        for (name, model) in loadedModels {
            do {
                try await warmupModel(name: name, model: model, dummyImage: dummyImage)
            } catch {
                logger.warning("Warmup failed for model \(name): \(error.localizedDescription)")
                // Continue with other models
            }
        }
        
        logger.info("Core ML model warmup completed")
    }
    
    private func warmupModel(name: String, model: MLModel, dummyImage: CVPixelBuffer?) async throws {
        logger.debug("Warming up model: \(name)")
        
        switch name {
        case CoreMLModelDefinitions.serialRegionDetectorName:
            if let image = dummyImage {
                let input = try MLDictionaryFeatureProvider(dictionary: [
                    CoreMLModelDefinitions.SerialRegionDetector.inputName: MLFeatureValue(pixelBuffer: image)
                ])
                _ = try await model.prediction(from: input)
            }
            
        case CoreMLModelDefinitions.serialFormatClassifierName:
            let textFeatures = try MLMultiArray(shape: [1, 128], dataType: .float32)
            let geometryFeatures = try MLMultiArray(shape: [1, 8], dataType: .float32)
            
            let input = try MLDictionaryFeatureProvider(dictionary: [
                CoreMLModelDefinitions.SerialFormatClassifier.inputTextName: MLFeatureValue(multiArray: textFeatures),
                CoreMLModelDefinitions.SerialFormatClassifier.inputGeometryName: MLFeatureValue(multiArray: geometryFeatures)
            ])
            _ = try await model.prediction(from: input)
            
        case CoreMLModelDefinitions.characterDisambiguatorName:
            if let image = createDummyPixelBuffer(width: 32, height: 32) {
                let input = try MLDictionaryFeatureProvider(dictionary: [
                    CoreMLModelDefinitions.CharacterDisambiguator.inputName: MLFeatureValue(pixelBuffer: image)
                ])
                _ = try await model.prediction(from: input)
            }
            
        default:
            logger.warning("Unknown model for warmup: \(name)")
        }
        
        logger.debug("Warmup completed for model: \(name)")
    }
    
    private func createDummyPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            logger.error("Failed to create dummy pixel buffer")
            return nil
        }
        
        // Fill with neutral gray
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            let bufferSize = bytesPerRow * height
            memset(baseAddress, 128, bufferSize) // Fill with gray
        }
        
        return buffer
    }
    
    // MARK: - Memory Management
    
    /// Clear all loaded models to free memory
    public func clearAllModels() {
        logger.info("Clearing all loaded Core ML models")
        loadedModels.removeAll()
        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks.removeAll()
        
        Task { @MainActor in
            isWarmupComplete = false
            loadingProgress.removeAll()
        }
    }
    
    /// Get memory usage statistics
    public func getMemoryUsage() -> [String: Any] {
        return [
            "loaded_models_count": loadedModels.count,
            "models_loaded": Array(loadedModels.keys),
            "warmup_complete": isWarmupComplete,
            "configuration": configuration.computeUnits.displayName
        ]
    }
}

// MARK: - Extensions

@available(iOS 13.0, *)
extension MLModelLoader {
    
    /// Convenience method to check if all models are loaded
    public var allModelsLoaded: Bool {
        let requiredModels = [
            CoreMLModelDefinitions.serialRegionDetectorName,
            CoreMLModelDefinitions.serialFormatClassifierName,
            CoreMLModelDefinitions.characterDisambiguatorName
        ]
        
        return requiredModels.allSatisfy { loadedModels.keys.contains($0) }
    }
    
    /// Get loading status for UI display
    public var loadingStatus: String {
        if isWarmupComplete {
            return "Ready"
        } else if loadingTasks.isEmpty && !loadedModels.isEmpty {
            return "Warming up..."
        } else if !loadingTasks.isEmpty {
            return "Loading models... (\(loadedModels.count)/3)"
        } else {
            return "Not loaded"
        }
    }
}
