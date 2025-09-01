import SwiftUI

/// View that displays surface detection status and confidence
struct SurfaceIndicatorView: View {
    @ObservedObject var viewModel: SerialScannerViewModel

    var body: some View {
        HStack(spacing: 8) {
            // Surface type icon
            Image(systemName: viewModel.detectedSurfaceType.iconName)
                .foregroundColor(iconColor)
                .font(.system(size: 16, weight: .medium))

            // Surface type text
            Text(viewModel.detectedSurfaceType.description)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)

            // Confidence indicator (only show if detected)
            if viewModel.detectedSurfaceType != .unknown && viewModel.surfaceDetectionConfidence > 0 {
                HStack(spacing: 4) {
                    // Confidence bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background bar
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 4)

                            // Confidence fill
                            RoundedRectangle(cornerRadius: 2)
                                .fill(confidenceColor)
                                .frame(width: geometry.size.width * CGFloat(viewModel.surfaceDetectionConfidence), height: 4)
                        }
                    }
                    .frame(width: 40, height: 4)

                    // Confidence percentage
                    Text("\(Int(viewModel.surfaceDetectionConfidence * 100))%")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(backgroundColor)
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
        .opacity(viewModel.isSurfaceDetectionEnabled ? 1.0 : 0.6)
        .animation(.easeInOut(duration: 0.3), value: viewModel.detectedSurfaceType)
        .animation(.easeInOut(duration: 0.3), value: viewModel.surfaceDetectionConfidence)
    }

    private var iconColor: Color {
        switch viewModel.detectedSurfaceType {
        case .metal:
            return .orange
        case .plastic:
            return .blue
        case .glass:
            return .cyan
        case .screen:
            return .green
        case .paper:
            return .yellow
        case .unknown:
            return .gray
        }
    }

    private var confidenceColor: Color {
        let confidence = viewModel.surfaceDetectionConfidence
        if confidence >= 0.8 {
            return .green
        } else if confidence >= 0.6 {
            return .yellow
        } else {
            return .red
        }
    }

    private var backgroundColor: Color {
        if viewModel.detectedSurfaceType == .unknown {
            return Color.black.opacity(0.6)
        } else {
            return Color.black.opacity(0.8)
        }
    }
}

/// Compact version for smaller displays
struct CompactSurfaceIndicatorView: View {
    @ObservedObject var viewModel: SerialScannerViewModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: viewModel.detectedSurfaceType.iconName)
                .foregroundColor(iconColor)
                .font(.system(size: 14, weight: .medium))

            if viewModel.detectedSurfaceType != .unknown {
                Text("\(Int(viewModel.surfaceDetectionConfidence * 100))%")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.black.opacity(0.7))
        )
        .opacity(viewModel.isSurfaceDetectionEnabled ? 1.0 : 0.5)
        .animation(.easeInOut(duration: 0.3), value: viewModel.detectedSurfaceType)
    }

    private var iconColor: Color {
        switch viewModel.detectedSurfaceType {
        case .metal:
            return .orange
        case .plastic:
            return .blue
        case .glass:
            return .cyan
        case .screen:
            return .green
        case .paper:
            return .yellow
        case .unknown:
            return .gray
        }
    }
}

struct SurfaceIndicatorView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = SerialScannerViewModel()

        VStack(spacing: 20) {
            SurfaceIndicatorView(viewModel: viewModel)
                .previewLayout(.sizeThatFits)
                .padding()

            CompactSurfaceIndicatorView(viewModel: viewModel)
                .previewLayout(.sizeThatFits)
                .padding()
        }
        .background(Color.gray.opacity(0.2))
    }
}
