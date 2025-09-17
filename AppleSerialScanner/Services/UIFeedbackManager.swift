import SwiftUI
import Combine
import os.log

/// Manages visual feedback and UI state for the scanner
class UIFeedbackManager: ObservableObject {
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "UIFeedback")
    
    // MARK: - Published Properties
    
    // Scanning state feedback
    @Published var feedbackState: FeedbackState = .waiting
    @Published var feedbackMessage: String = "Position serial number in frame"
    @Published var feedbackColor: Color = .white
    
    // Visual indicators
    @Published var showStabilityIndicator = false
    @Published var showQualityIndicator = true
    @Published var showGuidanceOverlay = true
    
    // ROI overlay
    @Published var roiOverlayOpacity: Double = 0.7
    @Published var roiHighlightColor: Color = .white
    @Published var showROIGuides = true
    
    // Motion feedback
    @Published var showMotionWarning = false
    @Published var motionWarningMessage = ""
    
    // Success feedback
    @Published var showSuccessAnimation = false
    @Published var lastSuccessTimestamp: Date?

    // Focus animation point (used by ScannerControlsView)
    @Published var focusAnimationPoint: CGPoint? = nil
    
    // Configuration
    private let feedbackDebounceInterval: TimeInterval = 0.5
    private var feedbackTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Dependencies

    private let qualityAnalyzer: FrameQualityAnalyzer
    private let guidanceService: ScanningGuidanceService

    init(qualityAnalyzer: FrameQualityAnalyzer, guidanceService: ScanningGuidanceService) {
        self.qualityAnalyzer = qualityAnalyzer
        self.guidanceService = guidanceService
        setupSubscriptions()
    }

    // MARK: - Public Methods

    /// Update feedback based on frame quality
    func updateFeedback(metrics: FrameQualityMetrics) {
        // Update stability indicator
        showStabilityIndicator = metrics.stabilityScore < 0.7
        
        // Update motion warning
        if metrics.stabilityScore < 0.5 {
            showMotionWarning = true
            motionWarningMessage = "Hold device steady"
        } else {
            showMotionWarning = false
        }
        
        // Update ROI highlight based on quality
        updateROIHighlight(metrics: metrics)
        
        // Update feedback state and message
        updateFeedbackState(metrics: metrics)
    }

    /// Show success feedback animation
    func showSuccess(message: String) {
        withAnimation {
            feedbackState = .success
            feedbackMessage = message
            feedbackColor = .green
            showSuccessAnimation = true
            lastSuccessTimestamp = Date()
        }
        
        // Reset success animation after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            withAnimation {
                self?.showSuccessAnimation = false
            }
        }
    }
    
    /// Show error feedback
    func showError(message: String) {
        withAnimation {
            feedbackState = .error
            feedbackMessage = message
            feedbackColor = .red
        }
        
        // Reset error state after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            withAnimation {
                self?.resetFeedbackState()
            }
        }
    }

    /// Reset feedback state
    func resetFeedbackState() {
        withAnimation {
            feedbackState = .waiting
            feedbackMessage = "Position serial number in frame"
            feedbackColor = .white
            showMotionWarning = false
            showSuccessAnimation = false
        }
    }

    /// Show a focus animation at the given normalized point (0..1)
    func showFocusAnimation(at point: CGPoint) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                self.focusAnimationPoint = point
            }
            // Remove after short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeIn(duration: 0.2)) {
                    self.focusAnimationPoint = nil
                }
            }
        }
    }

    // MARK: - Private Methods

    private func setupSubscriptions() {
        // Monitor guidance updates
        guidanceService.$guidanceMessage
            .sink { [weak self] message in
                self?.updateGuidance(message)
            }
            .store(in: &cancellables)

        // Monitor frame quality
        qualityAnalyzer.$lastQualityMetrics
            .sink { [weak self] (metrics: FrameQualityMetrics?) in
                if let metrics = metrics {
                    self?.updateFeedback(metrics: metrics)
                }
            }
            .store(in: &cancellables)
    }

    private func updateROIHighlight(metrics: FrameQualityMetrics) {
        let color: Color
        let opacity: Double
        
        if metrics.stabilityScore > 0.8 && metrics.clarityScore > 0.7 {
            color = .green
            opacity = 0.8
        } else if metrics.stabilityScore > 0.6 && metrics.clarityScore > 0.5 {
            color = .yellow
            opacity = 0.7
        } else {
            color = .white
            opacity = 0.6
        }
        
        withAnimation(.easeInOut(duration: 0.3)) {
            roiHighlightColor = color
            roiOverlayOpacity = opacity
        }
    }

    private func updateFeedbackState(metrics: FrameQualityMetrics) {
        let newState: FeedbackState
        let message: String
        let color: Color
        
        if metrics.stabilityScore < 0.5 {
            newState = .unstable
            message = "Hold device more steady"
            color = .yellow
        } else if metrics.clarityScore < 0.6 {
            newState = .poorQuality
            message = "Move closer to serial number"
            color = .yellow
        } else if metrics.brightnessScore < 0.4 {
            newState = .poorLighting
            message = "More light needed"
            color = .yellow
        } else if metrics.stabilityScore > 0.8 && metrics.clarityScore > 0.7 {
            newState = .ready
            message = "Good position - scanning"
            color = .green
        } else {
            newState = .scanning
            message = "Adjusting position..."
            color = .white
        }
        
        // Debounce rapid feedback changes
        debounceStateUpdate(state: newState, message: message, color: color)
    }

    private func updateGuidance(_ message: String) {
        // Update guidance overlay
        withAnimation {
            feedbackMessage = message
            showGuidanceOverlay = true
        }
        
        // Hide guidance after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            withAnimation {
                self?.showGuidanceOverlay = false
            }
        }
    }

    private func debounceStateUpdate(state: FeedbackState, message: String, color: Color) {
        feedbackTimer?.invalidate()
        
        feedbackTimer = Timer.scheduledTimer(withTimeInterval: feedbackDebounceInterval, repeats: false) { [weak self] _ in
            withAnimation {
                self?.feedbackState = state
                self?.feedbackMessage = message
                self?.feedbackColor = color
            }
        }
    }
}

// MARK: - Supporting Types

enum FeedbackState {
    case waiting
    case scanning
    case unstable
    case poorQuality
    case poorLighting
    case ready
    case success
    case error
}

struct FeedbackStyle {
    let backgroundColor: Color
    let textColor: Color
    let icon: String
    let animation: Animation
    
    static func style(for state: FeedbackState) -> FeedbackStyle {
        switch state {
        case .waiting:
            return FeedbackStyle(
                backgroundColor: .black.opacity(0.6),
                textColor: .white,
                icon: "camera.viewfinder",
                animation: Animation.default
            )
        case .scanning:
            return FeedbackStyle(
                backgroundColor: .blue.opacity(0.6),
                textColor: .white,
                icon: "camera.metering.center.weighted",
                animation: .easeInOut(duration: 0.3)
            )
        case .unstable:
            return FeedbackStyle(
                backgroundColor: .yellow.opacity(0.6),
                textColor: .black,
                icon: "hand.raised.fill",
                animation: .easeInOut(duration: 0.2)
            )
        case .poorQuality:
            return FeedbackStyle(
                backgroundColor: .orange.opacity(0.6),
                textColor: .white,
                icon: "camera.filters",
                animation: .easeInOut(duration: 0.3)
            )
        case .poorLighting:
            return FeedbackStyle(
                backgroundColor: .yellow.opacity(0.6),
                textColor: .black,
                icon: "light.min",
                animation: .easeInOut(duration: 0.3)
            )
        case .ready:
            return FeedbackStyle(
                backgroundColor: .green.opacity(0.6),
                textColor: .white,
                icon: "checkmark.circle.fill",
                animation: .spring(response: 0.3, dampingFraction: 0.7)
            )
        case .success:
            return FeedbackStyle(
                backgroundColor: .green.opacity(0.8),
                textColor: .white,
                icon: "checkmark.circle.fill",
                animation: .spring(response: 0.3, dampingFraction: 0.7)
            )
        case .error:
            return FeedbackStyle(
                backgroundColor: .red.opacity(0.8),
                textColor: .white,
                icon: "exclamationmark.circle.fill",
                animation: .easeInOut(duration: 0.3)
            )
        }
    }
}
