import SwiftUI
import Combine
import AVFoundation

/// Manages accessibility features and voice guidance for the scanner
class AccessibilityManager: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "Accessibility")
    
    // MARK: - Published Properties
    
    @Published var isVoiceGuidanceEnabled = true
    @Published var isHapticFeedbackEnabled = true
    @Published var isHighContrastModeEnabled = false
    @Published var currentVoiceGuidance: String = ""
    
    // Voice settings
    private let voiceRate: Float = 0.5
    private let voicePitch: Float = 1.0
    private let voiceVolume: Float = 0.8
    
    // Debounce configuration
    private let guidanceDebounceInterval: TimeInterval = 2.0
    private var lastGuidanceTime: Date = Date()
    
    // Haptic generators
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationHaptic = UINotificationFeedbackGenerator()
    
    init() {
        setupHaptics()
    }
    
    // MARK: - Public Methods
    
    /// Provide voice guidance for current state
    func provideGuidance(for state: FeedbackState, message: String) {
        guard isVoiceGuidanceEnabled else { return }
        
        let now = Date()
        guard now.timeIntervalSince(lastGuidanceTime) >= guidanceDebounceInterval else {
            return
        }
        
        speakGuidance(message)
        lastGuidanceTime = now
        currentVoiceGuidance = message
        
        if isHapticFeedbackEnabled {
            provideFeedback(for: state)
        }
    }
    
    /// Provide success feedback
    func signalSuccess() {
        if isHapticFeedbackEnabled {
            notificationHaptic.notificationOccurred(.success)
        }
        
        if isVoiceGuidanceEnabled {
            speakGuidance("Serial number successfully scanned")
        }
    }
    
    /// Provide error feedback
    func signalError(message: String) {
        if isHapticFeedbackEnabled {
            notificationHaptic.notificationOccurred(.error)
        }
        
        if isVoiceGuidanceEnabled {
            speakGuidance(message)
        }
    }
    
    /// Provide stability feedback
    func signalStabilityChange(isStable: Bool) {
        guard isHapticFeedbackEnabled else { return }
        
        if isStable {
            lightHaptic.impactOccurred()
        } else {
            mediumHaptic.impactOccurred()
        }
    }
    
    /// Get high contrast colors if needed
    func adaptiveColor(_ color: Color, defaultOpacity: Double = 1.0) -> Color {
        guard isHighContrastModeEnabled else {
            return color.opacity(defaultOpacity)
        }
        
        // Enhance contrast for better visibility
        return color
            .saturated(by: 1.2)
            .opacity(min(1.0, defaultOpacity * 1.3))
    }
    
    /// Get accessible text size
    func accessibleFontSize(_ baseSize: CGFloat) -> CGFloat {
        let contentSize = UIApplication.shared.preferredContentSizeCategory
        let sizeMultiplier = contentSize.isAccessibilityCategory ? 1.5 : 1.0
        return baseSize * sizeMultiplier
    }
    
    // MARK: - Private Methods
    
    private func setupHaptics() {
        lightHaptic.prepare()
        mediumHaptic.prepare()
        heavyHaptic.prepare()
        notificationHaptic.prepare()
    }
    
    private func speakGuidance(_ message: String) {
        // Stop any current speech
        synthesizer.stopSpeaking(at: .immediate)
        
        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = voiceRate
        utterance.pitchMultiplier = voicePitch
        utterance.volume = voiceVolume
        
        // Use enhanced quality voice
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        
        synthesizer.speak(utterance)
    }
    
    private func provideFeedback(for state: FeedbackState) {
        switch state {
        case .ready:
            lightHaptic.impactOccurred()
        case .success:
            notificationHaptic.notificationOccurred(.success)
        case .error:
            notificationHaptic.notificationOccurred(.error)
        case .unstable:
            mediumHaptic.impactOccurred()
        case .poorQuality, .poorLighting:
            lightHaptic.impactOccurred(intensity: 0.5)
        default:
            break
        }
    }
}

// MARK: - Accessibility View Modifiers

extension View {
    /// Add accessibility guidance to a view
    func withAccessibilityGuidance(
        _ message: String,
        importance: AccessibilityImportance = .default
    ) -> some View {
        self.modifier(AccessibilityGuidanceModifier(
            message: message,
            importance: importance
        ))
    }
    
    /// Add scanner-specific accessibility traits
    func scannerAccessibility(
        isEnabled: Bool = true,
        hint: String? = nil
    ) -> some View {
        self.modifier(ScannerAccessibilityModifier(
            isEnabled: isEnabled,
            hint: hint
        ))
    }
}

/// Modifier for adding accessibility guidance
struct AccessibilityGuidanceModifier: ViewModifier {
    let message: String
    let importance: AccessibilityImportance
    
    func body(content: Content) -> some View {
        content
            .accessibility(label: Text(message))
            .accessibility(addTraits: importance == .high ? .isHeader : [])
    }
}

/// Modifier for scanner-specific accessibility
struct ScannerAccessibilityModifier: ViewModifier {
    let isEnabled: Bool
    let hint: String?
    
    func body(content: Content) -> some View {
        content
            .accessibility(enabled: isEnabled)
            .accessibility(addTraits: .updatesFrequently)
            .accessibility(hint: hint.map(Text.init))
    }
}

enum AccessibilityImportance {
    case high
    case `default`
    case low
}

// MARK: - Color Extensions

extension Color {
    func saturated(by amount: Double) -> Color {
        guard let components = UIColor(self).cgColor.components else {
            return self
        }
        
        let red = pow(components[0], 1/amount)
        let green = pow(components[1], 1/amount)
        let blue = pow(components[2], 1/amount)
        
        return Color(
            red: Double(red),
            green: Double(green),
            blue: Double(blue)
        )
    }
}
