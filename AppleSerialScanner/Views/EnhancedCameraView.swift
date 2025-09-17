import SwiftUI
import AVFoundation
import Combine

/// Enhanced camera control view with real-time feedback and guidance
struct EnhancedCameraView: View {
    @StateObject private var cameraManager: CameraManager
    @StateObject private var guidanceService = ScanningGuidanceService()
    
    // Camera state
    @State private var isAutoAdjustEnabled = true
    @State private var showSettings = false
    @State private var roiBounds: CGRect = .zero
    
    init() {
        _cameraManager = StateObject(wrappedValue: CameraManager())
    }
    
    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(session: cameraManager.session)
                .overlay(
                    ROIOverlayView(
                        guidanceService: guidanceService,
                        roiBounds: calculateROIBounds()
                    )
                )
            
            // Camera controls and indicators
            VStack {
                // Top controls
                HStack {
                    settingsButton
                    Spacer()
                    autoAdjustToggle
                }
                .padding()
                
                Spacer()
                
                // Bottom indicators
                VStack(spacing: 16) {
                    if let quality = cameraManager.currentFrameQuality {
                        LightingIndicatorView(
                            brightnessLevel: quality.brightnessScore,
                            stabilityScore: quality.stabilityScore
                        )
                        
                        StabilityIndicatorView(
                            stabilityScore: quality.stabilityScore,
                            isStable: cameraManager.isFrameStable
                        )
                    }
                }
                .padding(.bottom, 32)
            }
            
            // Settings sheet
            .sheet(isPresented: $showSettings) {
                CameraSettingsView(
                    isAutoAdjustEnabled: $isAutoAdjustEnabled,
                    cameraManager: cameraManager
                )
            }
        }
        .onAppear {
            setupCamera()
        }
        .onChange(of: cameraManager.currentFrameQuality) { quality in
            if let metrics = quality {
                guidanceService.updateGuidance(metrics: metrics)
            }
        }
    }
    
    // MARK: - Private Views
    
    private var settingsButton: some View {
        Button(action: { showSettings = true }) {
            Image(systemName: "gear")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .padding(12)
                .background(Color.black.opacity(0.6))
                .clipShape(Circle())
        }
    }
    
    private var autoAdjustToggle: some View {
        Button(action: toggleAutoAdjust) {
            HStack(spacing: 8) {
                Image(systemName: isAutoAdjustEnabled ? "wand.and.stars" : "wand.and.stars.inverse")
                Text(isAutoAdjustEnabled ? "Auto" : "Manual")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(8)
            .background(Color.black.opacity(0.6))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Private Methods
    
    private func setupCamera() {
        cameraManager.isAutoAdjustEnabled = isAutoAdjustEnabled
        if !cameraManager.isSessionRunning {
            cameraManager.startSession()
        }
    }
    
    private func toggleAutoAdjust() {
        isAutoAdjustEnabled.toggle()
        cameraManager.isAutoAdjustEnabled = isAutoAdjustEnabled
        
        if !isAutoAdjustEnabled {
            // Reset to default camera settings when disabling auto-adjust
            cameraManager.resetCameraSettings()
        }
    }
    
    private func calculateROIBounds() -> CGRect {
        #if canImport(UIKit)
        let screenBounds = UIScreen.main.bounds
        #elseif canImport(AppKit)
        let screenBounds = NSScreen.main?.frame ?? .zero
        #else
        let screenBounds = .zero
        #endif

        let width = screenBounds.width * 0.8
        let height = width * 0.3 // Aspect ratio suitable for serial numbers

        return CGRect(
            x: (screenBounds.width - width) / 2,
            y: (screenBounds.height - height) / 2,
            width: width,
            height: height
        )
    }
}

/// Camera settings configuration view
struct CameraSettingsView: View {
    @Binding var isAutoAdjustEnabled: Bool
    let cameraManager: CameraManager
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Camera Controls")) {
                    Toggle("Auto Adjustment", isOn: $isAutoAdjustEnabled)
                        .onChange(of: isAutoAdjustEnabled) { newValue in
                            cameraManager.isAutoAdjustEnabled = newValue
                        }
                }
                
                Section(header: Text("Frame Quality")) {
                    if let quality = cameraManager.currentFrameQuality {
                        qualityRow("Clarity", value: quality.clarityScore)
                        qualityRow("Brightness", value: quality.brightnessScore)
                        qualityRow("Stability", value: quality.stabilityScore)
                    }
                }
            }
            .navigationTitle("Camera Settings")
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
    
    private func qualityRow(_ label: String, value: Float) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(String(format: "%.2f", value))
                .foregroundColor(qualityColor(value))
        }
    }
    
    private func qualityColor(_ value: Float) -> Color {
        if value >= 0.8 {
            return .green
        } else if value >= 0.6 {
            return .yellow
        } else {
            return .red
        }
    }
}
