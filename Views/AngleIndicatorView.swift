import SwiftUI

/// View that displays text orientation and angle correction status
struct AngleIndicatorView: View {
    @ObservedObject var viewModel: SerialScannerViewModel

    var body: some View {
        HStack(spacing: 8) {
            // Angle icon
            Image(systemName: angleIconName)
                .foregroundColor(iconColor)
                .font(.system(size: 16, weight: .medium))

            // Angle information
            VStack(alignment: .leading, spacing: 2) {
                if let orientation = viewModel.detectedTextOrientation, orientation.confidence > 0.5 {
                    HStack(spacing: 4) {
                        Text("\(Int(orientation.rotationAngle))°")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)

                        // Confidence indicator
                        RoundedRectangle(cornerRadius: 2)
                            .fill(confidenceColor)
                            .frame(width: 20, height: 4)
                    }

                    // Angle status text
                    Text(angleStatusText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.white.opacity(0.8))
                } else {
                    Text("Analyzing...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
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
        .opacity(viewModel.isAngleDetectionEnabled ? 1.0 : 0.6)
        .animation(.easeInOut(duration: 0.3), value: viewModel.detectedTextOrientation?.rotationAngle)
        .animation(.easeInOut(duration: 0.3), value: viewModel.detectedTextOrientation?.confidence)
    }

    private var angleIconName: String {
        guard let orientation = viewModel.detectedTextOrientation, orientation.confidence > 0.5 else {
            return "angle"
        }

        let angle = abs(orientation.rotationAngle)
        if angle < 5 {
            return "arrow.up"
        } else if angle < 45 {
            return "arrow.up.right"
        } else {
            return "arrow.right"
        }
    }

    private var iconColor: Color {
        guard let orientation = viewModel.detectedTextOrientation, orientation.confidence > 0.5 else {
            return .gray
        }

        let angle = abs(orientation.rotationAngle)
        if angle < 5 {
            return .green  // Good alignment
        } else if angle < 30 {
            return .yellow // Minor adjustment needed
        } else {
            return .orange // Significant adjustment needed
        }
    }

    private var confidenceColor: Color {
        guard let orientation = viewModel.detectedTextOrientation else {
            return .gray
        }

        let confidence = orientation.confidence
        if confidence > 0.8 {
            return .green
        } else if confidence > 0.6 {
            return .yellow
        } else {
            return .red
        }
    }

    private var angleStatusText: String {
        guard let orientation = viewModel.detectedTextOrientation else {
            return "Unknown"
        }

        let angle = abs(orientation.rotationAngle)
        if angle < 5 {
            return "Optimal"
        } else if angle < 15 {
            return "Good"
        } else if angle < 30 {
            return "Fair"
        } else {
            return "Poor"
        }
    }

    private var backgroundColor: Color {
        guard let orientation = viewModel.detectedTextOrientation, orientation.confidence > 0.5 else {
            return Color.black.opacity(0.6)
        }

        let angle = abs(orientation.rotationAngle)
        if angle < 5 {
            return Color.green.opacity(0.8)
        } else if angle < 30 {
            return Color.yellow.opacity(0.8)
        } else {
            return Color.orange.opacity(0.8)
        }
    }
}

/// Compact version for smaller displays
struct CompactAngleIndicatorView: View {
    @ObservedObject var viewModel: SerialScannerViewModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: angleIconName)
                .foregroundColor(iconColor)
                .font(.system(size: 14, weight: .medium))

            if let orientation = viewModel.detectedTextOrientation, orientation.confidence > 0.5 {
                Text("\(Int(orientation.rotationAngle))°")
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
        .opacity(viewModel.isAngleDetectionEnabled ? 1.0 : 0.5)
        .animation(.easeInOut(duration: 0.3), value: viewModel.detectedTextOrientation?.rotationAngle)
    }

    private var angleIconName: String {
        guard let orientation = viewModel.detectedTextOrientation, orientation.confidence > 0.5 else {
            return "angle"
        }

        let angle = abs(orientation.rotationAngle)
        if angle < 5 {
            return "arrow.up"
        } else if angle < 45 {
            return "arrow.up.right"
        } else {
            return "arrow.right"
        }
    }

    private var iconColor: Color {
        guard let orientation = viewModel.detectedTextOrientation, orientation.confidence > 0.5 else {
            return .gray
        }

        let angle = abs(orientation.rotationAngle)
        if angle < 5 {
            return .green
        } else if angle < 30 {
            return .yellow
        } else {
            return .orange
        }
    }
}

struct AngleIndicatorView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = SerialScannerViewModel()

        VStack(spacing: 20) {
            AngleIndicatorView(viewModel: viewModel)
                .previewLayout(.sizeThatFits)
                .padding()

            CompactAngleIndicatorView(viewModel: viewModel)
                .previewLayout(.sizeThatFits)
                .padding()
        }
        .background(Color.gray.opacity(0.2))
    }
}
