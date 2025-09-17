import SwiftUI
import Combine
import AVFoundation
import os.log

/// Manages accessibility features and voice guidance for the scanner
class AccessibilityManager: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "Accessibility")
    
    // MARK: - Published Properties

    @Published var isVoiceGuidanceEnabled: Bool = true
    @Published var isHapticFeedbackEnabled: Bool = true
    @Published var isHighContrastModeEnabled: Bool = false
    @Published var currentVoiceGuidance: String = ""

    // Voice settings
    private let voiceRate: Float = 0.5
    private let voicePitch: Float = 1.0
    private let voiceVolume: Float = 0.8
    
    // Debounce configuration
    private let guidanceDebounceInterval: TimeInterval = 2.0
    private var lastGuidanceTime: Date = Date()
    
    // Haptic generators
    #if canImport(UIKit)
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let mediumHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationHaptic = UINotificationFeedbackGenerator()
    #else
    // On platforms without UIKit (macOS) provide no-op placeholders
    private struct NoopHaptic {
        func prepare() {}
        func impactOccurred(intensity: Double = 1.0) {}
        func impactOccurred() {}
        // Accept optional param to avoid requiring UIKit enum values on macOS
        func notificationOccurred(_ _: Any? = nil) {}
    }
    private let lightHaptic = NoopHaptic()
    private let mediumHaptic = NoopHaptic()
    private let heavyHaptic = NoopHaptic()
    private let notificationHaptic = NoopHaptic()
    #endif

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
            #if canImport(UIKit)
            notificationHaptic.notificationOccurred(.success)
            #else
            notificationHaptic.notificationOccurred()
            #endif
        }
        
        if isVoiceGuidanceEnabled {
            speakGuidance("Serial number successfully scanned")
        }
    }
    
    /// Provide error feedback
    func signalError(message: String) {
        if isHapticFeedbackEnabled {
            #if canImport(UIKit)
            notificationHaptic.notificationOccurred(.error)
            #else
            notificationHaptic.notificationOccurred()
            #endif
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
        #if canImport(UIKit)
        let contentSize = UIApplication.shared.preferredContentSizeCategory
        let sizeMultiplier = contentSize.isAccessibilityCategory ? 1.5 : 1.0
        return baseSize * sizeMultiplier
        #else
        // macOS: return base size (no dynamic type)
        return baseSize
        #endif
    }

    // MARK: - Private Methods
    
    private func setupHaptics() {
        #if canImport(UIKit)
        lightHaptic.prepare()
        mediumHaptic.prepare()
        heavyHaptic.prepare()
        notificationHaptic.prepare()
        #else
        // no-op on macOS
        lightHaptic.prepare()
        mediumHaptic.prepare()
        heavyHaptic.prepare()
        notificationHaptic.prepare()
        #endif
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
            // Notification feedback maps to appropriate call on UIKit; on macOS this is a noop
            #if canImport(UIKit)
            notificationHaptic.notificationOccurred(.success)
            #else
            notificationHaptic.notificationOccurred()
            #endif
        case .error:
            #if canImport(UIKit)
            notificationHaptic.notificationOccurred(.error)
            #else
            notificationHaptic.notificationOccurred()
            #endif
        case .unstable:
            mediumHaptic.impactOccurred()
        case .poorQuality, .poorLighting:
            // impactOccurred(intensity:) exists only on some platforms; keep conservative call
            lightHaptic.impactOccurred()
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

/// Modifier for scanner-specific accessibility
struct ScannerAccessibilityModifier: ViewModifier {
    let isEnabled: Bool
    let hint: String?

    func body(content: Content) -> some View {
        if let hint = hint {
            return AnyView(
                content
                    .accessibility(hidden: !isEnabled)
                    .accessibility(addTraits: .updatesFrequently)
                    .accessibilityHint(Text(hint))
            )
        } else {
            return AnyView(
                content
                    .accessibility(hidden: !isEnabled)
                    .accessibility(addTraits: .updatesFrequently)
            )
        }
    }
}

/// Modifier for adding accessibility guidance
struct AccessibilityGuidanceModifier: ViewModifier {
    let message: String
    let importance: AccessibilityImportance

    func body(content: Content) -> some View {
        if importance == .high {
            return AnyView(
                content
                    .accessibility(label: Text(message))
                    .accessibility(addTraits: .isHeader)
            )
        } else {
            return AnyView(
                content
                    .accessibility(label: Text(message))
            )
        }
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
        #if canImport(UIKit)
        if let ui = UIColor(self).cgColor.components, ui.count >= 3 {
            let red = pow(ui[0], 1/amount)
            let green = pow(ui[1], 1/amount)
            let blue = pow(ui[2], 1/amount)
            return Color(red: Double(red), green: Double(green), blue: Double(blue))
        }
        return self
        #elseif canImport(AppKit)
        let ns = NSColor(self)
        guard let rgb = ns.usingColorSpace(.deviceRGB) else { return self }
        let red = pow(Double(rgb.redComponent), 1/amount)
        let green = pow(Double(rgb.greenComponent), 1/amount)
        let blue = pow(Double(rgb.blueComponent), 1/amount)
        return Color(red: red, green: green, blue: blue)
        #else
        return self
        #endif
    }
}
