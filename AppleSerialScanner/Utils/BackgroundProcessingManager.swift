import Foundation
import Vision
import CoreImage
import UIKit

/// Manages background processing tasks to improve performance and prevent UI blocking
class BackgroundProcessingManager {
    // MARK: - Processing Queues with QoS
    private let ocrProcessingQueue = DispatchQueue(label: "com.appleserial.ocr.processing", qos: .userInteractive)
    private let analyticsProcessingQueue = DispatchQueue(label: "com.appleserial.analytics.processing", qos: .utility)
    private let surfaceProcessingQueue = DispatchQueue(label: "com.appleserial.surface.processing", qos: .userInitiated)
    
    // MARK: - Throttling Properties
    private var lastFrameProcessingTime = Date()
    private var frameSkipCounter = 0
    private let processingThrottle: TimeInterval = 0.05 // 50ms minimum between frames
    
    // MARK: - Processing State
    private var isProcessingFrame = false
    private var pendingTasks = 0
    private let processingLock = NSLock()
    
    // MARK: - Device-Specific Settings
    private let deviceType: DeviceType
    private var adaptiveFrameSkip: Int {
        switch deviceType {
        case .iPad:
            return 2 // Skip every 2nd frame on iPad (higher resolution needs more processing)
        case .iPhone:
            return 1 // Skip every other frame on iPhone
        case .mac:
            return 0 // Process all frames on Mac (generally more powerful)
        }
    }
    
    enum DeviceType {
        case iPad, iPhone, mac
    }
    
    // MARK: - Initialization
    init() {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == UIUserInterfaceIdiom.pad {
            deviceType = .iPad
        } else {
            deviceType = .iPhone
        }
        #else
        deviceType = .mac
        #endif
    }
    
    // MARK: - Frame Processing Management
    
    /// Determines if a frame should be processed based on device capabilities and current load
    func shouldProcessFrame() -> Bool {
        // Adaptive frame skipping based on device type
        frameSkipCounter += 1
        if adaptiveFrameSkip > 0 && frameSkipCounter % (adaptiveFrameSkip + 1) != 0 {
            return false
        }
        
        // Throttle processing to prevent overwhelming the device
        let timeNow = Date()
        if timeNow.timeIntervalSince(lastFrameProcessingTime) < processingThrottle {
            return false
        }
        
        // Check if we're already processing a frame
        processingLock.lock()
        defer { processingLock.unlock() }
        if isProcessingFrame {
            return false
        }
        
        lastFrameProcessingTime = timeNow
        return true
    }
    
    /// Marks the beginning of frame processing
    func beginFrameProcessing() {
        processingLock.lock()
        isProcessingFrame = true
        processingLock.unlock()
    }
    
    /// Marks the end of frame processing
    func endFrameProcessing() {
        processingLock.lock()
        isProcessingFrame = false
        processingLock.unlock()
    }
    
    // MARK: - OCR Processing
    
    /// Processes text recognition in the background with high priority
    func processTextRecognition(handler: VNImageRequestHandler, request: VNRequest, completion: @escaping (Error?) -> Void) {
        ocrProcessingQueue.async {
            do {
                try handler.perform([request])
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }
    
    // MARK: - Surface & Lighting Detection
    
    /// Processes surface detection in the background with medium priority
    func processSurfaceDetection(image: CIImage, completion: @escaping (BackgroundSurfaceDetectionResult) -> Void) {
        incrementPendingTasks()
        
        surfaceProcessingQueue.async {
            // Surface detection logic would be called here
            // This would normally call surfaceDetector.detectSurface
            
            self.decrementPendingTasks()
            
            // This is a placeholder - the actual implementation would use your SurfaceDetector
            let result = BackgroundSurfaceDetectionResult(surfaceType: .unknown, confidence: 0.0)
            completion(result)
        }
    }
    
    /// Processes lighting analysis in the background with medium priority
    func processLightingAnalysis(image: CIImage, completion: @escaping (BackgroundLightingCondition, Float) -> Void) {
        incrementPendingTasks()
        
        surfaceProcessingQueue.async {
            // Lighting analysis logic would be called here
            // This would normally call lightingAnalyzer.analyzeIllumination
            
            self.decrementPendingTasks()
            
            // This is a placeholder - the actual implementation would use your LightingAnalyzer
            completion(.unknown, 0.0)
        }
    }
    
    // MARK: - Analytics Processing
    
    /// Processes analytics data in the background with low priority
    func processAnalytics(eventType: String, data: [String: Any], completion: @escaping () -> Void) {
        incrementPendingTasks()
        
        analyticsProcessingQueue.async {
            // Process analytics in background with lowest priority
            // This prevents analytics from interfering with scanning performance
            
            // Simulate analytics processing time
            Thread.sleep(forTimeInterval: 0.01)
            
            self.decrementPendingTasks()
            completion()
        }
    }
    
    // MARK: - Task Management
    
    private func incrementPendingTasks() {
        processingLock.lock()
        pendingTasks += 1
        processingLock.unlock()
    }
    
    private func decrementPendingTasks() {
        processingLock.lock()
        pendingTasks -= 1
        processingLock.unlock()
    }
    
    /// Returns the number of pending background tasks
    var pendingTaskCount: Int {
        processingLock.lock()
        defer { processingLock.unlock() }
        return pendingTasks
    }
    
    /// Determines if the system is under heavy load based on pending tasks
    var isUnderHeavyLoad: Bool {
        return pendingTaskCount > 5
    }
}

// MARK: - Helper Structs

// Renamed to avoid ambiguity with SurfaceDetector types
struct BackgroundSurfaceDetectionResult {
    let surfaceType: BackgroundSurfaceType
    let confidence: Float
}

enum BackgroundSurfaceType: String, CaseIterable {
    case unknown
    case metal
    case plastic
    case glass
    case screen
    case paper
    
    var description: String {
        switch self {
        case .unknown: return "Unknown"
        case .metal: return "Metal"
        case .plastic: return "Plastic"
        case .glass: return "Glass"
        case .screen: return "Screen"
        case .paper: return "Paper"
        }
    }
}

enum BackgroundLightingCondition: String {
    case unknown
    case bright
    case dim
    case mixed
    case glare
    
    var description: String {
        switch self {
        case .unknown: return "Unknown"
        case .bright: return "Bright"
        case .dim: return "Dim"
        case .mixed: return "Mixed"
        case .glare: return "Glare"
        }
    }
}
