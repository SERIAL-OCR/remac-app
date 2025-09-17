import SwiftUI

/// Enhanced scanner overlay with visual feedback and guidance
struct EnhancedScannerOverlay: View {
    @ObservedObject var feedbackManager: UIFeedbackManager
    let roiBounds: CGRect
    
    private let cornerLength: CGFloat = 24
    private let lineWidth: CGFloat = 2.5
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background mask
                MaskedBackgroundView(
                    roiBounds: roiBounds,
                    opacity: feedbackManager.roiOverlayOpacity
                )
                
                // ROI corners with dynamic color
                EnhancedROICornerGuides(
                    bounds: roiBounds,
                    cornerLength: cornerLength,
                    lineWidth: lineWidth,
                    color: feedbackManager.roiHighlightColor
                )
                
                // Feedback indicators
                Group {
                    if feedbackManager.showStabilityIndicator {
                        StabilityIndicator()
                            .position(
                                x: roiBounds.maxX + 40,
                                y: roiBounds.midY
                            )
                    }
                    
                    if feedbackManager.showQualityIndicator {
                        QualityIndicator(quality: calculateQuality())
                            .position(
                                x: roiBounds.minX - 40,
                                y: roiBounds.midY
                            )
                    }
                }
                
                // Guidance overlay
                if feedbackManager.showGuidanceOverlay {
                    GuidanceOverlay(
                        message: feedbackManager.feedbackMessage,
                        state: feedbackManager.feedbackState
                    )
                    .position(
                        x: geometry.size.width / 2,
                        y: roiBounds.maxY + 50
                    )
                }
                
                // Motion warning
                if feedbackManager.showMotionWarning {
                    MotionWarning(message: feedbackManager.motionWarningMessage)
                        .position(
                            x: geometry.size.width / 2,
                            y: roiBounds.minY - 50
                        )
                }
                
                // Success animation
                if feedbackManager.showSuccessAnimation {
                    SuccessAnimation()
                        .position(
                            x: geometry.size.width / 2,
                            y: geometry.size.height / 2
                        )
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
    
    private func calculateQuality() -> Double {
        // This would be calculated based on various metrics
        return 0.8
    }
}

/// Masked background view with cutout for ROI
struct MaskedBackgroundView: View {
    let roiBounds: CGRect
    let opacity: Double
    
    var body: some View {
        Rectangle()
            .fill(Color.black)
            .opacity(opacity)
            .mask(
                Rectangle()
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .frame(
                                width: roiBounds.width,
                                height: roiBounds.height
                            )
                            .position(
                                x: roiBounds.midX,
                                y: roiBounds.midY
                            )
                            .blendMode(.destinationOut)
                    )
            )
    }
}

/// Dynamic corner guides for ROI
struct EnhancedROICornerGuides: View {
    let bounds: CGRect
    let cornerLength: CGFloat
    let lineWidth: CGFloat
    let color: Color
    
    var body: some View {
        ZStack {
            // Top left corner
            CornerShape(length: cornerLength)
                .stroke(color, lineWidth: lineWidth)
                .position(x: bounds.minX, y: bounds.minY)
            
            // Top right corner
            CornerShape(length: cornerLength)
                .rotation(.degrees(90))
                .stroke(color, lineWidth: lineWidth)
                .position(x: bounds.maxX, y: bounds.minY)
            
            // Bottom left corner
            CornerShape(length: cornerLength)
                .rotation(.degrees(270))
                .stroke(color, lineWidth: lineWidth)
                .position(x: bounds.minX, y: bounds.maxY)
            
            // Bottom right corner
            CornerShape(length: cornerLength)
                .rotation(.degrees(180))
                .stroke(color, lineWidth: lineWidth)
                .position(x: bounds.maxX, y: bounds.maxY)
        }
    }
}

/// Custom corner shape
struct CornerShape: Shape {
    let length: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: length))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: length, y: 0))
        return path
    }
}

/// Guidance overlay with dynamic styling
struct GuidanceOverlay: View {
    let message: String
    let state: FeedbackState
    
    var body: some View {
        let style = FeedbackStyle.style(for: state)
        
        HStack(spacing: 8) {
            Image(systemName: style.icon)
                .font(.system(size: 20))
            
            Text(message)
                .font(.system(size: 16, weight: .medium))
        }
        .foregroundColor(style.textColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(style.backgroundColor)
        .cornerRadius(10)
        .shadow(radius: 4)
        .animation(style.animation, value: state)
    }
}

/// Motion warning indicator
struct MotionWarning: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 20))
            
            Text(message)
                .font(.system(size: 16, weight: .medium))
        }
        .foregroundColor(.black)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.yellow.opacity(0.8))
        .cornerRadius(10)
        .shadow(radius: 4)
    }
}

/// Quality indicator with circular progress
struct QualityIndicator: View {
    let quality: Double
    
    var body: some View {
        Circle()
            .trim(from: 0, to: quality)
            .stroke(
                quality > 0.7 ? Color.green : Color.yellow,
                style: StrokeStyle(
                    lineWidth: 3,
                    lineCap: .round
                )
            )
            .rotationEffect(.degrees(-90))
            .frame(width: 30, height: 30)
            .animation(.spring(), value: quality)
    }
}

/// Stability indicator with pulse animation
struct StabilityIndicator: View {
    @State private var isAnimating = false
    
    var body: some View {
        Image(systemName: "hand.raised.fill")
            .font(.system(size: 24))
            .foregroundColor(.yellow)
            .scaleEffect(isAnimating ? 1.2 : 1.0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.5)
                    .repeatForever(autoreverses: true)
                ) {
                    isAnimating = true
                }
            }
    }
}

/// Success animation overlay
struct SuccessAnimation: View {
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.3))
                .frame(width: 100, height: 100)
                .scaleEffect(scale)
                .opacity(opacity)
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
                .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                scale = 1.2
                opacity = 1
            }
        }
    }
}
