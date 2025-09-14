import SwiftUI
import CoreGraphics

/// Interactive ROI overlay view with dynamic feedback
struct ROIOverlayView: View {
    @ObservedObject var guidanceService: ScanningGuidanceService
    let roiBounds: CGRect
    
    private let cornerLength: CGFloat = 20
    private let lineWidth: CGFloat = 2.5
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Semi-transparent background mask
                Rectangle()
                    .fill(Color.black)
                    .opacity(guidanceService.overlayOpacity)
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
                
                // ROI corner guides
                ROICornerGuides(
                    bounds: roiBounds,
                    cornerLength: cornerLength,
                    lineWidth: lineWidth,
                    color: guidanceService.guidanceColor
                )
                
                // Guidance message
                if guidanceService.showGuideOverlay {
                    Text(guidanceService.guidanceMessage)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(guidanceService.guidanceColor)
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                        .position(
                            x: geometry.size.width / 2,
                            y: roiBounds.maxY + 40
                        )
                }
                
                // Stability indicator
                if guidanceService.isOptimalPosition {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.green)
                        .position(
                            x: roiBounds.maxX + 30,
                            y: roiBounds.midY
                        )
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}

/// Corner guide shapes for ROI visualization
struct ROICornerGuides: View {
    let bounds: CGRect
    let cornerLength: CGFloat
    let lineWidth: CGFloat
    let color: Color
    
    var body: some View {
        ZStack {
            // Top left corner
            CornerPath(length: cornerLength, lineWidth: lineWidth)
                .stroke(color, lineWidth: lineWidth)
                .position(x: bounds.minX, y: bounds.minY)
            
            // Top right corner
            CornerPath(length: cornerLength, lineWidth: lineWidth)
                .rotation(.degrees(90))
                .stroke(color, lineWidth: lineWidth)
                .position(x: bounds.maxX, y: bounds.minY)
            
            // Bottom left corner
            CornerPath(length: cornerLength, lineWidth: lineWidth)
                .rotation(.degrees(270))
                .stroke(color, lineWidth: lineWidth)
                .position(x: bounds.minX, y: bounds.maxY)
            
            // Bottom right corner
            CornerPath(length: cornerLength, lineWidth: lineWidth)
                .rotation(.degrees(180))
                .stroke(color, lineWidth: lineWidth)
                .position(x: bounds.maxX, y: bounds.maxY)
        }
    }
}

/// Custom corner path shape
struct CornerPath: Shape {
    let length: CGFloat
    let lineWidth: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        path.move(to: CGPoint(x: 0, y: length))
        path.addLine(to: CGPoint(x: 0, y: lineWidth))
        path.addLine(to: CGPoint(x: length, y: lineWidth))
        
        return path
    }
}
