import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct CleanScannerOverlayView: View {
    @ObservedObject var viewModel: SerialScannerViewModel
    @State private var roiRect: CGRect = .zero
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    // Helper to calculate ROI
    private func calculateROI(size: CGSize) -> CGRect {
        let roiWidth: CGFloat
        let roiHeight: CGFloat
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            roiWidth = min(size.width * 0.7, 600)
            roiHeight = roiWidth * 0.25
        } else {
            roiWidth = size.width * 0.8
            roiHeight = roiWidth * 0.3
        }
        #else
        // macOS: treat as iPad-like layout for larger screens
        roiWidth = min(size.width * 0.7, 800)
        roiHeight = roiWidth * 0.25
        #endif
        return CGRect(
            x: (size.width - roiWidth) / 2.0,
            y: (size.height - roiHeight) / 2.0,
            width: roiWidth,
            height: roiHeight
        )
    }
    
    var body: some View {
        GeometryReader { geometry in
            let roi = calculateROI(size: geometry.size)
            ZStack {
                // Semi-transparent overlay
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .ignoresSafeArea()
                
                // Create cutout with a subtle glow
                Rectangle()
                    .path(in: roi)
                    .fill(Color.clear)
                    .blendMode(.destinationOut)
                
                // ROI outline - subtle rounded rectangle
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: roi.width, height: roi.height)
                    .position(x: roi.midX, y: roi.midY)
                    .shadow(color: Color.white.opacity(0.7), radius: 4, x: 0, y: 0)
                
                // Corner brackets for visual focus
                Group {
                    // Top left corner
                    CornerBracket()
                        .position(x: roi.minX + 15, y: roi.minY + 15)
                    
                    // Top right corner
                    CornerBracket(direction: .topRight)
                        .position(x: roi.maxX - 15, y: roi.minY + 15)
                    
                    // Bottom left corner
                    CornerBracket(direction: .bottomLeft)
                        .position(x: roi.minX + 15, y: roi.maxY - 15)
                    
                    // Bottom right corner
                    CornerBracket(direction: .bottomRight)
                        .position(x: roi.maxX - 15, y: roi.maxY - 15)
                }
                
                // Update ROI in view model
                Color.clear
                    .onAppear {
                        roiRect = roi
                        viewModel.updateRegionOfInterest(from: roi, in: CGRect(origin: .zero, size: geometry.size))
                    }
                    .onChange(of: geometry.size) { _ in
                        let updated = calculateROI(size: geometry.size)
                        roiRect = updated
                        viewModel.updateRegionOfInterest(from: updated, in: CGRect(origin: .zero, size: geometry.size))
                    }
                
                // Clean, minimal guidance text at the bottom
                VStack {
                    Spacer()
                    
                    Text(viewModel.guidanceText.components(separatedBy: "\n").first ?? "Position serial number in frame")
                        .foregroundColor(.white)
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                        .padding(.bottom, bottomPadding())
                        .multilineTextAlignment(.center)
                }
                
                // Optional preset selector button - positioned for iPad
                #if os(iOS)
                if UIDevice.current.userInterfaceIdiom == .pad {
                    VStack {
                        HStack {
                            Spacer()
                            
                            Button(action: {
                                viewModel.showingPresetSelector = true
                            }) {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                            }
                            .padding(.top, 60)
                            .padding(.trailing, 30)
                        }
                        Spacer()
                    }
                }
                #endif
            }
            .compositingGroup()
        }
    }

    private func bottomPadding() -> CGFloat {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? 80 : 50
        #else
        return 80
        #endif
    }
}

// Corner bracket for visual guidance
struct CornerBracket: View {
    enum Direction {
        case topLeft, topRight, bottomLeft, bottomRight
    }
    
    var direction: Direction = .topLeft
    var length: CGFloat = 20
    var thickness: CGFloat = 3
    
    var body: some View {
        ZStack {
            // Horizontal line
            Rectangle()
                .fill(Color.white)
                .frame(width: length, height: thickness)
                .offset(
                    x: direction == .topLeft || direction == .bottomLeft ? length/4 : -length/4,
                    y: 0
                )
            
            // Vertical line
            Rectangle()
                .fill(Color.white)
                .frame(width: thickness, height: length)
                .offset(
                    x: 0,
                    y: direction == .topLeft || direction == .topRight ? length/4 : -length/4
                )
        }
        .rotationEffect(.degrees(
            direction == .topLeft ? 0 :
            direction == .topRight ? 90 :
            direction == .bottomLeft ? 270 :
            180
        ))
        .shadow(color: Color.white.opacity(0.7), radius: 2, x: 0, y: 0)
    }
}

// Preview
struct CleanScannerOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        CleanScannerOverlayView(viewModel: SerialScannerViewModel())
            .previewLayout(.sizeThatFits)
            .preferredColorScheme(.dark)
    }
}
