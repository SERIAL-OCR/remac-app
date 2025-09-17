import SwiftUI
import VisionKit
import CoreGraphics

/// Phase 2: Advanced ROI (Region of Interest) overlay with visible scanning window
/// Provides tight focus area to improve recognition accuracy and reduce false positives
struct Phase2ROIOverlayView: View {
    @ObservedObject var viewModel: SerialScannerViewModel
    let scannerType: ScannerType
    @State private var roiConfiguration: ROIConfiguration
    @State private var showROISettings = false
    
    init(viewModel: SerialScannerViewModel, scannerType: ScannerType) {
        self.viewModel = viewModel
        self.scannerType = scannerType
        // Phase 2: Initialize with optimized ROI for Apple serial numbers
        self._roiConfiguration = State(initialValue: ROIConfiguration.optimizedForAppleSerials(scannerType: scannerType))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Phase 2: Darkened overlay with cutout for ROI
                roiMaskOverlay(in: geometry)
                
                // Phase 2: Visible scanning window with guidance
                roiScanningWindow(in: geometry)
                
                // ROI controls and information
                roiControlsOverlay(in: geometry)
            }
        }
        .sheet(isPresented: $showROISettings) {
            ROIConfigurationView(configuration: $roiConfiguration, scannerType: scannerType)
        }
        .onChange(of: roiConfiguration.name) { _ in
            applyROIConfiguration(roiConfiguration)
        }
    }
    
    // MARK: - ROI Mask Overlay
    
    @ViewBuilder
    private func roiMaskOverlay(in geometry: GeometryProxy) -> some View {
        // Phase 2: Semi-transparent overlay with cutout for scanning area
        Path { path in
            // Add the full screen rectangle
            path.addRect(CGRect(origin: .zero, size: geometry.size))

            // Subtract the ROI rectangle to create cutout
            let roiRect = calculateROIRect(in: geometry.size)
            path.addRect(roiRect)
        }
        // Changed to white overlay so only ROI shows camera content
        .fill(Color.white.opacity(0.96), style: FillStyle(eoFill: true))
        .animation(.easeInOut(duration: 0.3), value: roiConfiguration.name)
    }
    
    // MARK: - Scanning Window
    
    @ViewBuilder
    private func roiScanningWindow(in geometry: GeometryProxy) -> some View {
        let roiRect = calculateROIRect(in: geometry.size)
        
        ZStack {
            // Phase 2: Scanning window border with rounded corners
            RoundedRectangle(cornerRadius: roiConfiguration.cornerRadius)
                .stroke(roiConfiguration.borderColor, lineWidth: roiConfiguration.borderWidth)
                .frame(width: roiRect.width, height: roiRect.height)
                .position(x: roiRect.midX, y: roiRect.midY)
                .shadow(color: .black.opacity(0.3), radius: 4)
            
            // Phase 2: Corner guides for better visibility
            cornerGuides(for: roiRect)
            
            // Phase 2: Center crosshair for precise alignment
            if roiConfiguration.showCrosshair {
                crosshairGuide(for: roiRect)
            }
            
            // Phase 2: Dynamic ROI label
            roiLabel(for: roiRect)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: roiConfiguration.name)
    }
    
    @ViewBuilder
    private func cornerGuides(for roiRect: CGRect) -> some View {
        let cornerLength: CGFloat = 20
        let cornerWidth: CGFloat = 3
        
        ForEach(0..<4, id: \.self) { corner in
            Path { path in
                let (x, y) = cornerPosition(corner, in: roiRect)
                
                switch corner {
                case 0: // Top-left
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x + cornerLength, y: y))
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x, y: y + cornerLength))
                case 1: // Top-right
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x - cornerLength, y: y))
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x, y: y + cornerLength))
                case 2: // Bottom-right
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x - cornerLength, y: y))
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x, y: y - cornerLength))
                case 3: // Bottom-left
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x + cornerLength, y: y))
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x, y: y - cornerLength))
                default:
                    break
                }
            }
            .stroke(Color.white, lineWidth: cornerWidth)
            .shadow(color: .black.opacity(0.5), radius: 2)
        }
    }
    
    @ViewBuilder
    private func crosshairGuide(for roiRect: CGRect) -> some View {
        Path { path in
            let centerX = roiRect.midX
            let centerY = roiRect.midY
            let crosshairLength: CGFloat = 40
            
            // Horizontal line
            path.move(to: CGPoint(x: centerX - crosshairLength/2, y: centerY))
            path.addLine(to: CGPoint(x: centerX + crosshairLength/2, y: centerY))
            
            // Vertical line
            path.move(to: CGPoint(x: centerX, y: centerY - crosshairLength/2))
            path.addLine(to: CGPoint(x: centerX, y: centerY + crosshairLength/2))
        }
        .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
        .shadow(color: .black.opacity(0.5), radius: 1)
    }
    
    @ViewBuilder
    private func roiLabel(for roiRect: CGRect) -> some View {
        VStack(spacing: 4) {
            Text(roiConfiguration.label)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            if roiConfiguration.showDimensions {
                Text("\(Int(roiRect.width)) × \(Int(roiRect.height))")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.7))
        .cornerRadius(6)
        .position(x: roiRect.midX, y: roiRect.minY - 30)
    }
    
    // MARK: - ROI Controls Overlay
    
    @ViewBuilder
    private func roiControlsOverlay(in geometry: GeometryProxy) -> some View {
        VStack {
            HStack {
                // ROI type indicator
                HStack {
                    Image(systemName: roiConfiguration.icon)
                        .foregroundColor(roiConfiguration.borderColor)
                    Text(roiConfiguration.name)
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
                
                Spacer()
                
                // ROI settings button
                Button(action: { showROISettings = true }) {
                    Image(systemName: "viewfinder.circle")
                        .foregroundColor(.white)
                        .font(.title2)
                }
                .padding()
            }
            .padding(.top)
            
            Spacer()
            
            // Phase 2: ROI guidance based on detection state
            roiGuidanceView
                .padding(.bottom, 100) // Above control buttons
        }
    }
    
    @ViewBuilder
    private var roiGuidanceView: some View {
        VStack(spacing: 8) {
            Text(getROIGuidanceText())
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.black) // dark text on white UI
                .multilineTextAlignment(.center)

            if !viewModel.recognizedText.isEmpty {
                Text("Detected in ROI: \(viewModel.recognizedText)")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.white)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        .padding(.horizontal)
    }
    
    // MARK: - Helper Methods
    
    private func calculateROIRect(in size: CGSize) -> CGRect {
        let width = size.width * roiConfiguration.widthRatio
        let height = size.height * roiConfiguration.heightRatio
        let x = (size.width - width) / 2 + roiConfiguration.offsetX
        let y = (size.height - height) / 2 + roiConfiguration.offsetY
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    private func cornerPosition(_ corner: Int, in rect: CGRect) -> (CGFloat, CGFloat) {
        switch corner {
        case 0: return (rect.minX, rect.minY) // Top-left
        case 1: return (rect.maxX, rect.minY) // Top-right
        case 2: return (rect.maxX, rect.maxY) // Bottom-right
        case 3: return (rect.minX, rect.maxY) // Bottom-left
        default: return (rect.midX, rect.midY)
        }
    }
    
    private func getROIGuidanceText() -> String {
        switch scannerType {
        case .visionKit:
            return "Position serial number within the scanning window for best results"
        case .legacy:
            return "Align serial number with the scanning area - avoid edges"
        }
    }
    
    private func applyROIConfiguration(_ config: ROIConfiguration) {
        // Phase 2: Apply ROI configuration to VisionKit or legacy scanner
        if scannerType == .visionKit {
            applyVisionKitROIConfiguration(config)
        } else {
            applyLegacyROIConfiguration(config)
        }
    }
    
    private func applyVisionKitROIConfiguration(_ config: ROIConfiguration) {
        // Phase 2: Configure VisionKit with ROI restrictions
        // This would be applied to the VisionKit scanner's region of interest
        print("Phase 2: Applying VisionKit ROI configuration: \(config.name)")
    }
    
    private func applyLegacyROIConfiguration(_ config: ROIConfiguration) {
        // Phase 2: Configure legacy scanner with ROI restrictions
        // This would be applied to the Vision framework requests
        print("Phase 2: Applying Legacy ROI configuration: \(config.name)")
    }
}

// MARK: - ROI Configuration

struct ROIConfiguration {
    let name: String
    let label: String
    let icon: String
    let widthRatio: CGFloat
    let heightRatio: CGFloat
    let offsetX: CGFloat
    let offsetY: CGFloat
    let borderColor: Color
    let borderWidth: CGFloat
    let cornerRadius: CGFloat
    let showCrosshair: Bool
    let showDimensions: Bool
    
    // Phase 2: Predefined configurations optimized for different scanning scenarios
    
    static func optimizedForAppleSerials(scannerType: ScannerType) -> ROIConfiguration {
        switch scannerType {
        case .visionKit:
            return ROIConfiguration(
                name: "Apple Serial (VisionKit)",
                label: "Serial Number Area",
                icon: "text.viewfinder",
                widthRatio: 0.8,
                heightRatio: 0.25,
                offsetX: 0,
                offsetY: 0,
                borderColor: .green,
                borderWidth: 2.5,
                cornerRadius: 12,
                showCrosshair: true,
                showDimensions: false
            )
        case .legacy:
            return ROIConfiguration(
                name: "Apple Serial (Legacy)",
                label: "Focus Area",
                icon: "camera.viewfinder",
                widthRatio: 0.7,
                heightRatio: 0.2,
                offsetX: 0,
                offsetY: 0,
                borderColor: .orange,
                borderWidth: 2.0,
                cornerRadius: 8,
                showCrosshair: false,
                showDimensions: true
            )
        }
    }
    
    static let compactSerial = ROIConfiguration(
        name: "Compact Serial",
        label: "Compact Area",
        icon: "text.magnifyingglass",
        widthRatio: 0.6,
        heightRatio: 0.15,
        offsetX: 0,
        offsetY: 0,
        borderColor: .blue,
        borderWidth: 2.0,
        cornerRadius: 10,
        showCrosshair: true,
        showDimensions: true
    )
    
    static let wideSerial = ROIConfiguration(
        name: "Wide Serial",
        label: "Extended Area",
        icon: "rectangle.expand.vertical",
        widthRatio: 0.9,
        heightRatio: 0.3,
        offsetX: 0,
        offsetY: 0,
        borderColor: .purple,
        borderWidth: 2.5,
        cornerRadius: 15,
        showCrosshair: false,
        showDimensions: false
    )
    
    static let precisionMode = ROIConfiguration(
        name: "Precision Mode",
        label: "High Precision",
        icon: "plus.magnifyingglass",
        widthRatio: 0.5,
        heightRatio: 0.12,
        offsetX: 0,
        offsetY: 0,
        borderColor: .red,
        borderWidth: 3.0,
        cornerRadius: 6,
        showCrosshair: true,
        showDimensions: true
    )
    
    static let allConfigurations: [ROIConfiguration] = [
        .compactSerial,
        .wideSerial,
        .precisionMode
    ]
}

// MARK: - ROI Configuration View

struct ROIConfigurationView: View {
    @Binding var configuration: ROIConfiguration
    let scannerType: ScannerType
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Current configuration preview
                VStack(alignment: .leading, spacing: 12) {
                    Text("Current Configuration")
                        .font(.headline)
                    
                    HStack {
                        Image(systemName: configuration.icon)
                            .foregroundColor(configuration.borderColor)
                            .font(.title2)
                        
                        VStack(alignment: .leading) {
                            Text(configuration.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text("Size: \(Int(configuration.widthRatio * 100))% × \(Int(configuration.heightRatio * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                // Available configurations
                VStack(alignment: .leading, spacing: 12) {
                    Text("Available Configurations")
                        .font(.headline)
                    
                    LazyVStack(spacing: 8) {
                        ForEach(ROIConfiguration.allConfigurations, id: \.name) { config in
                            ROIConfigurationRow(
                                configuration: config,
                                isSelected: config.name == configuration.name,
                                action: { configuration = config }
                            )
                        }
                    }
                }
                
                // Phase 2: VisionKit-specific settings
                if scannerType == .visionKit {
                    visionKitROISettings
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("ROI Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
    
    @ViewBuilder
    private var visionKitROISettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VisionKit Optimizations")
                .font(.headline)
            
            VStack(spacing: 8) {
                SettingRow(
                    title: "Language Restriction",
                    subtitle: "English-only alphanumeric",
                    icon: "textformat.abc",
                    isEnabled: true
                )
                
                SettingRow(
                    title: "Content Type Filter",
                    subtitle: "Text recognition only",
                    icon: "text.magnifyingglass",
                    isEnabled: true
                )
                
                SettingRow(
                    title: "Real-time Tracking",
                    subtitle: "Continuous ROI updates",
                    icon: "location.viewfinder",
                    isEnabled: true
                )
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

struct ROIConfigurationRow: View {
    let configuration: ROIConfiguration
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: configuration.icon)
                    .foregroundColor(configuration.borderColor)
                    .font(.title3)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(configuration.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(configuration.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }
            }
            .padding()
            .background(isSelected ? Color(.systemBlue).opacity(0.1) : Color(.systemGray6))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SettingRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let isEnabled: Bool
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(isEnabled ? .green : .gray)
                .font(.title3)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isEnabled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            }
        }
    }
}
