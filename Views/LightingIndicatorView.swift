import SwiftUI

/// View that displays lighting condition status and confidence
struct LightingIndicatorView: View {
    @ObservedObject var viewModel: SerialScannerViewModel

    var body: some View {
        HStack(spacing: 8) {
            // Lighting condition icon
            Image(systemName: viewModel.detectedLightingCondition.iconName)
                .foregroundColor(iconColor)
                .font(.system(size: 16, weight: .medium))

            // Lighting condition text
            Text(viewModel.detectedLightingCondition.description)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)

            // Brightness indicator (only show if detected)
            if viewModel.detectedLightingCondition != .unknown && viewModel.lightingDetectionConfidence > 0 {
                HStack(spacing: 4) {
                    // Brightness bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background bar
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 4)

                            // Brightness fill
                            RoundedRectangle(cornerRadius: 2)
                                .fill(brightnessColor)
                                .frame(width: geometry.size.width * CGFloat(viewModel.lightingDetectionConfidence), height: 4)
                        }
                    }
                    .frame(width: 40, height: 4)

                    // Brightness percentage
                    Text("\(Int(viewModel.lightingDetectionConfidence * 100))%")
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
        .opacity(viewModel.isLightingDetectionEnabled ? 1.0 : 0.6)
        .animation(.easeInOut(duration: 0.3), value: viewModel.detectedLightingCondition)
        .animation(.easeInOut(duration: 0.3), value: viewModel.lightingDetectionConfidence)
    }

    private var iconColor: Color {
        switch viewModel.detectedLightingCondition {
        case .optimal:
            return .green
        case .bright:
            return .yellow
        case .dim:
            return .blue
        case .uneven:
            return .orange
        case .glare:
            return .red
        case .mixed:
            return .purple
        case .unknown:
            return .gray
        }
    }

    private var brightnessColor: Color {
        let brightness = viewModel.lightingDetectionConfidence
        if brightness > 0.7 {
            return .yellow
        } else if brightness > 0.4 {
            return .green
        } else {
            return .blue
        }
    }

    private var backgroundColor: Color {
        if viewModel.detectedLightingCondition == .unknown {
            return Color.black.opacity(0.6)
        } else {
            return Color.black.opacity(0.8)
        }
    }
}

/// Compact version for smaller displays
struct CompactLightingIndicatorView: View {
    @ObservedObject var viewModel: SerialScannerViewModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: viewModel.detectedLightingCondition.iconName)
                .foregroundColor(iconColor)
                .font(.system(size: 14, weight: .medium))

            if viewModel.detectedLightingCondition != .unknown {
                Text("\(Int(viewModel.lightingDetectionConfidence * 100))%")
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
        .opacity(viewModel.isLightingDetectionEnabled ? 1.0 : 0.5)
        .animation(.easeInOut(duration: 0.3), value: viewModel.detectedLightingCondition)
    }

    private var iconColor: Color {
        switch viewModel.detectedLightingCondition {
        case .optimal:
            return .green
        case .bright:
            return .yellow
        case .dim:
            return .blue
        case .uneven:
            return .orange
        case .glare:
            return .red
        case .mixed:
            return .purple
        case .unknown:
            return .gray
        }
    }
}

struct LightingIndicatorView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = SerialScannerViewModel()

        VStack(spacing: 20) {
            LightingIndicatorView(viewModel: viewModel)
                .previewLayout(.sizeThatFits)
                .padding()

            CompactLightingIndicatorView(viewModel: viewModel)
                .previewLayout(.sizeThatFits)
                .padding()
        }
        .background(Color.gray.opacity(0.2))
    }
}
