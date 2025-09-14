import SwiftUI

/// Interactive scanner controls with haptic feedback
struct ScannerControlsView: View {
    @ObservedObject var feedbackManager: UIFeedbackManager
    @ObservedObject var accessibilityManager: AccessibilityManager
    
    let onTapToFocus: (CGPoint) -> Void
    let onZoom: (CGFloat) -> Void
    
    @GestureState private var dragState = CGSize.zero
    @State private var lastScale: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            // Invisible interactive layer
            Color.clear
                .contentShape(Rectangle())
                // Tap gesture for focus
                .onTapGesture { location in
                    let point = CGPoint(
                        x: location.x / geometry.size.width,
                        y: location.y / geometry.size.height
                    )
                    handleTap(at: point)
                }
                // Magnification gesture for zoom
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale in
                            handleZoom(scale: scale)
                        }
                        .onEnded { scale in
                            lastScale *= scale
                        }
                )
                // Double tap to reset
                .onTapGesture(count: 2) {
                    handleReset()
                }
                // Accessibility
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Scanner control area")
                .accessibilityHint("Tap to focus, pinch to zoom")
        }
    }
    
    private func handleTap(at point: CGPoint) {
        // Provide haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        // Call focus handler
        onTapToFocus(point)
        
        // Update UI feedback
        feedbackManager.showFocusAnimation(at: point)
        
        // Voice guidance if enabled
        if accessibilityManager.isVoiceGuidanceEnabled {
            accessibilityManager.provideGuidance(
                for: .scanning,
                message: "Focusing at tapped location"
            )
        }
    }
    
    private func handleZoom(scale: CGFloat) {
        // Calculate zoom factor
        let delta = (scale - 1.0) * 0.5
        let newScale = lastScale * (1.0 + delta)
        
        // Limit zoom range
        let limitedScale = min(max(newScale, 1.0), 5.0)
        
        // Call zoom handler
        onZoom(limitedScale)
        
        // Provide subtle haptic feedback
        if abs(limitedScale - lastScale) > 0.1 {
            let generator = UIImpactFeedbackGenerator(style: .soft)
            generator.impactOccurred(intensity: 0.5)
        }
    }
    
    private func handleReset() {
        // Reset zoom
        lastScale = 1.0
        onZoom(1.0)
        
        // Reset feedback state
        feedbackManager.resetFeedbackState()
        
        // Provide feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        if accessibilityManager.isVoiceGuidanceEnabled {
            accessibilityManager.provideGuidance(
                for: .waiting,
                message: "Scanner view reset"
            )
        }
    }
}

/// Focus animation overlay
struct FocusAnimationView: View {
    let point: CGPoint
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            // Outer circle
            Circle()
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: isAnimating ? 100 : 40, height: isAnimating ? 100 : 40)
                .opacity(isAnimating ? 0 : 0.8)
            
            // Inner circle
            Circle()
                .fill(Color.white)
                .frame(width: 4, height: 4)
        }
        .position(point)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                isAnimating = true
            }
        }
    }
}

/// Zoom level indicator
struct ZoomIndicatorView: View {
    let zoomLevel: CGFloat
    @State private var isVisible = false
    
    var body: some View {
        Text(String(format: "%.1fx", zoomLevel))
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.6))
            .cornerRadius(4)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isVisible = true
                }
                
                // Auto-hide after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isVisible = false
                    }
                }
            }
    }
}

/// Interactive help overlay
struct InteractiveHelpOverlay: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentStep = 0
    
    let helpSteps = [
        HelpStep(
            title: "Tap to Focus",
            message: "Tap anywhere on the screen to focus on that area",
            icon: "hand.tap"
        ),
        HelpStep(
            title: "Pinch to Zoom",
            message: "Pinch in or out to adjust zoom level",
            icon: "hand.draw"
        ),
        HelpStep(
            title: "Double Tap to Reset",
            message: "Double tap to reset zoom and focus",
            icon: "arrow.counterclockwise"
        )
    ]
    
    var body: some View {
        ZStack {
            // Background dimming
            Color.black.opacity(0.7)
                .edgesIgnoringSafeArea(.all)
            
            // Help content
            VStack(spacing: 24) {
                // Icon
                Image(systemName: helpSteps[currentStep].icon)
                    .font(.system(size: 44))
                    .foregroundColor(.white)
                
                // Text
                VStack(spacing: 8) {
                    Text(helpSteps[currentStep].title)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(helpSteps[currentStep].message)
                        .font(.body)
                        .multilineTextAlignment(.center)
                }
                .foregroundColor(.white)
                
                // Navigation
                HStack(spacing: 20) {
                    if currentStep > 0 {
                        Button("Previous") {
                            withAnimation {
                                currentStep -= 1
                            }
                        }
                    }
                    
                    if currentStep < helpSteps.count - 1 {
                        Button("Next") {
                            withAnimation {
                                currentStep += 1
                            }
                        }
                    } else {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.bordered)
                .foregroundColor(.white)
            }
            .padding()
        }
    }
}

struct HelpStep {
    let title: String
    let message: String
    let icon: String
}
