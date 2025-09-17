import SwiftUI
import VisionKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Phase 1: Enhanced device-aware scanner with VisionKit live scanning integration
/// Phase 2: Enhanced with tight ROI overlay and visible scanning window
/// Automatically selects VisionKit DataScannerViewController when available,
/// falls back to legacy AVFoundation implementation on older devices
struct DeviceTypeAwareScannerView: View {
    @ObservedObject var viewModel: SerialScannerViewModel
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State private var scannerType: ScannerType
    @State private var showingCompatibilityInfo = false
    
    init(viewModel: SerialScannerViewModel) {
        self.viewModel = viewModel
        // Phase 1: Determine optimal scanner type at initialization
        self._scannerType = State(initialValue: viewModel.getRecommendedScannerType())
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Phase 1: Scanner implementation selection
                scannerImplementationView
                
                // Phase 2: ROI overlay with visible scanning window
                Phase2ROIOverlayView(viewModel: viewModel, scannerType: scannerType)
                
                // Scanner overlay and controls
                Phase1ScannerOverlayView(viewModel: viewModel, scannerType: scannerType)
                
                // Compatibility info button (top-right)
                VStack {
                    HStack {
                        Spacer()
                        Button(action: { showingCompatibilityInfo = true }) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.white)
                                .font(.title2)
                                .shadow(radius: 2)
                        }
                        .padding()
                    }
                    Spacer()
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                setupScanner()
            }
            .sheet(isPresented: $showingCompatibilityInfo) {
                ScannerCompatibilityInfoView(scannerType: scannerType)
            }
        }
    }
    
    @ViewBuilder
    private var scannerImplementationView: some View {
        switch scannerType {
        case .visionKit:
            // Phase 1: VisionKit live scanning with continuous text tracking
            // Phase 2: Enhanced with ROI configuration and language restrictions
            if #available(iOS 16.0, *) {
                VisionKitLiveScannerView(viewModel: viewModel)
                    .ignoresSafeArea()
            } else {
                // Fallback should not happen due to getRecommendedScannerType logic
                legacyScannerView
            }
            
        case .legacy:
            // Legacy AVFoundation implementation
            legacyScannerView
        }
    }
    
    @ViewBuilder
    private var legacyScannerView: some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            // iPad-optimized legacy scanner
            CleanIPadScannerView(viewModel: viewModel)
        } else {
            // iPhone legacy scanner
            SerialScannerView(scannerViewModel: viewModel)
        }
        #else
        // macOS implementation
        SerialScannerView(scannerViewModel: viewModel)
        #endif
    }
    
    private func setupScanner() {
        // Phase 1: Log scanner selection for debugging and metrics
        let availabilityInfo = gatherCompatibilityInfo()
        
        print("""
        Phase 2 Scanner Selection:
        Selected: \(scannerType)
        VisionKit Available: \(availabilityInfo.isVisionKitAvailable)
        ROI Optimization: \(scannerType == .visionKit ? "Advanced" : "Basic")
        Device: \(availabilityInfo.deviceInfo)
        OS Version: \(availabilityInfo.osVersion)
        """)
        
        // Apply device-specific optimizations
        switch scannerType {
        case .visionKit:
            setupVisionKitOptimizations()
        case .legacy:
            setupLegacyOptimizations()
        }
    }
    
    private func setupVisionKitOptimizations() {
        // Phase 1: VisionKit-specific optimizations
        // Phase 2: ROI optimizations handled by VisionKit scanner
        viewModel.guidanceText = "Position serial within scanning window - VisionKit ROI active"
    }
    
    private func setupLegacyOptimizations() {
        // Legacy scanner optimizations with basic ROI
        viewModel.guidanceText = "Position serial within scanning area - Legacy ROI mode"
    }
    
    private func gatherCompatibilityInfo() -> CompatibilityInfo {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let deviceInfo: String
        
        #if os(iOS)
        deviceInfo = "\(UIDevice.current.model) - \(UIDevice.current.userInterfaceIdiom)"
        #else
        deviceInfo = "macOS"
        #endif
        
        return CompatibilityInfo(
            isVisionKitAvailable: SerialScannerViewModel.isVisionKitAvailable(),
            deviceInfo: deviceInfo,
            osVersion: osVersion,
            selectedScannerType: scannerType
        )
    }
}

// MARK: - Phase 1 Scanner Overlay View (Updated for Phase 2)

struct Phase1ScannerOverlayView: View {
    @ObservedObject var viewModel: SerialScannerViewModel
    let scannerType: ScannerType

    var body: some View {
        VStack {
            // New: editable white search bar / real-time text display
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)

                    // Bind the TextField to the viewModel.recognizedText so it's editable
                    TextField("Recognized text", text: Binding(
                        get: { viewModel.recognizedText },
                        set: { newValue in
                            viewModel.recognizedText = newValue
                        }
                    ))
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(.black)

                    if !viewModel.recognizedText.isEmpty {
                        Button(action: {
                            // Trigger submission of the edited/recognized text
                            Task { @MainActor in
                                viewModel.submitRecognizedText()
                            }
                        }) {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(10)
                .background(Color.white)
                .cornerRadius(10)
                .shadow(radius: 2)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 12)

            // Top status bar with Phase 2 ROI indicator
            HStack {
                // Scanner type indicator with ROI status
                HStack {
                    Image(systemName: scannerTypeIcon)
                        .foregroundColor(scannerTypeColor)
                    Text("\(scannerTypeText) + ROI")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)

                Spacer()

                // Baseline metrics toggle
                Button(action: viewModel.toggleBaselineMetrics) {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.white)
                        .font(.title2)
                }
                .padding()
            }
            .padding(.top)

            Spacer()

            // Phase 2: Enhanced guidance text for ROI scanning
            Text(getPhase2GuidanceText())
                .font(.headline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding()
                .background(Color.black.opacity(0.7))
                .cornerRadius(12)
                .padding(.horizontal)

            // Recognition results with ROI context
            if !viewModel.recognizedText.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Detected in ROI: \(viewModel.recognizedText)")
                            .font(.subheadline)
                            .foregroundColor(.white)

                        Text("Confidence: \(Int(viewModel.bestConfidence * 100))% • \(getROIStatus())")
                            .font(.caption)
                            .foregroundColor(confidenceColor)
                    }

                    Spacer()
                }
                .padding()
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
                .padding(.horizontal)
            }

            // New: Zoom slider (white UI) - placed above control buttons
            VStack(spacing: 6) {
                HStack {
                    Text("Zoom")
                        .font(.subheadline)
                        .foregroundColor(.black)

                    Spacer()

                    // Show the smoothed/displayed zoom value so UI matches camera ramping
                    Text(String(format: "%.2fx", viewModel.displayedZoom))
                        .font(.caption)
                        .foregroundColor(.black)
                }

                // Use viewModel-provided min/max supported zoom for the Slider range instead of hardcoded 1.0...5.0 so slider clamps correctly to device capability (same change as SerialScannerView).
                Slider(value: Binding(get: {
                    Double(viewModel.displayedZoom)
                }, set: { newVal in
                    viewModel.setDisplayedZoomTarget(CGFloat(newVal))
                }), in: Double(viewModel.minSupportedZoom)...Double(viewModel.maxSupportedZoom), onEditingChanged: { editing in
                    if !editing {
                        viewModel.setZoomFactor(viewModel.displayedZoomTarget)
                    }
                })
                .accentColor(.blue)
            }
            .padding(10)
            .background(Color.white)
            .cornerRadius(10)
            .shadow(radius: 2)
            .padding(.horizontal)
            .padding(.bottom, 6)

            // Control buttons
            HStack(spacing: 20) {
                Button(action: viewModel.startScanning) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start ROI")
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(8)
                }
                .disabled(viewModel.isScanning)

                Button(action: viewModel.stopScanning) {
                    HStack {
                        Image(systemName: "stop.fill")
                        Text("Stop")
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(8)
                }
                .disabled(!viewModel.isScanning)
            }
            .padding(.bottom)
        }
        .sheet(isPresented: $viewModel.showBaselineMetrics) {
            BaselineMetricsDashboard(viewModel: viewModel)
        }
    }

    private var scannerTypeIcon: String {
        switch scannerType {
        case .visionKit: return "eye.fill"
        case .legacy: return "camera.fill"
        }
    }

    private var scannerTypeColor: Color {
        switch scannerType {
        case .visionKit: return .green
        case .legacy: return .orange
        }
    }

    private var scannerTypeText: String {
        switch scannerType {
        case .visionKit: return "VisionKit"
        case .legacy: return "Legacy"
        }
    }

    private var confidenceColor: Color {
        if viewModel.bestConfidence > 0.8 { return .green }
        else if viewModel.bestConfidence > 0.6 { return .orange }
        else { return .red }
    }

    // Phase 2: Enhanced guidance text for ROI scanning
    private func getPhase2GuidanceText() -> String {
        switch scannerType {
        case .visionKit:
            if viewModel.isScanning {
                return "VisionKit ROI active - position serial in highlighted area"
            } else {
                return "Tap Start ROI to begin VisionKit scanning with focus area"
            }
        case .legacy:
            if viewModel.isScanning {
                return "Legacy ROI active - keep serial within scanning window"
            } else {
                return "Tap Start ROI to begin legacy scanning with focus area"
            }
        }
    }

    // Phase 2: ROI status indicator
    private func getROIStatus() -> String {
        switch scannerType {
        case .visionKit:
            return "Advanced ROI"
        case .legacy:
            return "Basic ROI"
        }
    }
}

// MARK: - Compatibility Info View (Updated for Phase 2)

struct ScannerCompatibilityInfoView: View {
    let scannerType: ScannerType
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                // Current implementation
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Implementation")
                        .font(.headline)
                    
                    HStack {
                        Image(systemName: scannerType == .visionKit ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(scannerType == .visionKit ? .green : .orange)
                        
                        Text(scannerType == .visionKit ? "VisionKit Live + Advanced ROI" : "Legacy Camera + Basic ROI")
                            .font(.subheadline)
                    }
                }
                
                // Phase 2: Updated features comparison with ROI
                VStack(alignment: .leading, spacing: 12) {
                    Text("Features")
                        .font(.headline)
                    
                    FeatureRow(title: "Live Text Tracking", visionKit: true, legacy: false)
                    FeatureRow(title: "Item Highlights", visionKit: true, legacy: false)
                    FeatureRow(title: "Built-in Guidance", visionKit: true, legacy: false)
                    FeatureRow(title: "Multiple Items", visionKit: true, legacy: false)
                    FeatureRow(title: "Continuous Updates", visionKit: true, legacy: false)
                    FeatureRow(title: "Advanced ROI", visionKit: true, legacy: false)
                    FeatureRow(title: "Language Restrictions", visionKit: true, legacy: false)
                    FeatureRow(title: "Visible Scanning Window", visionKit: true, legacy: true)
                    FeatureRow(title: "Performance Optimized", visionKit: true, legacy: true)
                }
                
                // Phase 2: ROI-specific requirements
                VStack(alignment: .leading, spacing: 8) {
                    Text("Phase 2: ROI Features")
                        .font(.headline)
                    
                    Text("• Visible scanning window with corner guides")
                    Text("• English-only alphanumeric text filtering")
                    Text("• Reduced false positives outside ROI")
                    Text("• Improved focus and exposure control")
                    Text("• Real-time ROI configuration")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                // Requirements
                VStack(alignment: .leading, spacing: 8) {
                    Text("VisionKit Requirements")
                        .font(.headline)
                    
                    Text("• iOS 16.0 or later")
                    Text("• Compatible device (iPhone XS/iPad 2018 or newer)")
                    Text("• Neural Engine support")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Scanner Info")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

struct FeatureRow: View {
    let title: String
    let visionKit: Bool
    let legacy: Bool
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
            
            Spacer()
            
            HStack(spacing: 16) {
                Image(systemName: visionKit ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(visionKit ? .green : .red)
                    .font(.caption)
                
                Image(systemName: legacy ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(legacy ? .green : .red)
                    .font(.caption)
            }
        }
    }
}

// MARK: - Supporting Types

struct CompatibilityInfo {
    let isVisionKitAvailable: Bool
    let deviceInfo: String
    let osVersion: String
    let selectedScannerType: ScannerType
}
