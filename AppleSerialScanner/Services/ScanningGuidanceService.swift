import Foundation
import CoreGraphics
import SwiftUI

/// Service providing real-time scanning guidance and user feedback
class ScanningGuidanceService: ObservableObject {
    // MARK: - Published Properties
    @Published var guidanceMessage: String = "Position serial number within frame"
    @Published var guidanceColor: Color = .white
    @Published var showGuideOverlay: Bool = true
    @Published var overlayOpacity: Double = 0.7
    @Published var isOptimalPosition: Bool = false
    
    // Guidance state
    private var currentStability: Float = 0.0
    private var currentClarity: Float = 0.0
    private var consecutiveGoodFrames: Int = 0
    private var lastGuidanceUpdate: Date = Date()
    
    // Configuration
    private let guidanceUpdateInterval: TimeInterval = 0.5
    private let requiredGoodFrames: Int = 3
    
    /// Update guidance based on current frame quality metrics
    func updateGuidance(metrics: FrameQualityMetrics) {
        let now = Date()
        guard now.timeIntervalSince(lastGuidanceUpdate) >= guidanceUpdateInterval else { return }
        
        currentStability = metrics.stabilityScore
        currentClarity = metrics.clarityScore
        
        // Track consecutive good frames
        if metrics.stabilityScore > 0.8 && metrics.clarityScore > 0.7 {
            consecutiveGoodFrames += 1
        } else {
            consecutiveGoodFrames = 0
        }
        
        isOptimalPosition = consecutiveGoodFrames >= requiredGoodFrames
        
        // Update guidance message and color based on current conditions
        updateGuidanceMessage(metrics: metrics)
        
        lastGuidanceUpdate = now
    }
    
    /// Reset guidance state
    func reset() {
        guidanceMessage = "Position serial number within frame"
        guidanceColor = .white
        showGuideOverlay = true
        overlayOpacity = 0.7
        isOptimalPosition = false
        consecutiveGoodFrames = 0
        currentStability = 0.0
        currentClarity = 0.0
    }
    
    // MARK: - Private Methods
    
    private func updateGuidanceMessage(metrics: FrameQualityMetrics) {
        // Determine the most important issue to address
        if metrics.stabilityScore < 0.6 {
            guidanceMessage = "Hold device more steady"
            guidanceColor = .yellow
            return
        }
        
        if metrics.brightnessScore < 0.4 {
            guidanceMessage = "More light needed"
            guidanceColor = .yellow
            return
        }
        
        if metrics.brightnessScore > 0.8 {
            guidanceMessage = "Reduce glare or bright light"
            guidanceColor = .yellow
            return
        }
        
        if metrics.averageTextSize < 30 {
            guidanceMessage = "Move closer to serial number"
            guidanceColor = .yellow
            return
        }
        
        if metrics.averageTextSize > 100 {
            guidanceMessage = "Move further from serial number"
            guidanceColor = .yellow
            return
        }
        
        if metrics.clarityScore < 0.7 {
            guidanceMessage = "Adjust focus"
            guidanceColor = .yellow
            return
        }
        
        // All conditions are good
        if isOptimalPosition {
            guidanceMessage = "Perfect position - hold steady"
            guidanceColor = .green
            overlayOpacity = 0.5
        } else {
            guidanceMessage = "Good position - hold steady"
            guidanceColor = .white
            overlayOpacity = 0.7
        }
    }
}
