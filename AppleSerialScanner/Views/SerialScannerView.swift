import SwiftUI
import Vision
import VisionKit
import AVFoundation
import Combine

struct SerialScannerView: View {
    @ObservedObject var scannerViewModel: SerialScannerViewModel
    @State private var showingSettings = false
    @State private var showingHistory = false
    // Local slider state to decouple UI thumb movement from authoritative camera zoom
    @State private var sliderValue: Double = 1.0
    @State private var isSliderEditing: Bool = false

    var body: some View {
        NavigationView {
            ZStack {
                if let previewLayer = scannerViewModel.previewLayer {
                    // Camera preview with overlay. Keep app chrome white; camera will be visible only through the ROI mask.
                    CameraPreviewView(previewLayer: previewLayer)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white)
                        .ignoresSafeArea()
                } else {
                    // Fallback UI if camera is not available
                    VStack {
                        Spacer()
                        Image(systemName: "camera.slash")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .foregroundColor(.gray)
                        Text("Camera not available")
                            .font(.title2)
                            .foregroundColor(.gray)
                        Text("Check camera permissions or try restarting the app.")
                            .font(.body)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .background(Color.white.ignoresSafeArea())
                }
                // Real-time editable detected text field (search bar) anchored at top
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Detected text", text: $scannerViewModel.recognizedText, onCommit: {
                            // Fallback for older SwiftUI versions
                            scannerViewModel.submitRecognizedText()
                        })
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6)))
                            .textInputAutocapitalization(.characters)
                            .disableAutocorrection(true)
                            .submitLabel(.search)
                            .onSubmit {
                                scannerViewModel.submitRecognizedText()
                            }
                            .accessibilityLabel("Detected serial input")

                        Button(action: {
                            scannerViewModel.submitRecognizedText()
                        }) {
                            Text("Submit")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)

                    Spacer()
                }
                
                // ROI overlay and guidance (masking so only ROI shows camera)
                ScannerOverlayView(scannerViewModel: scannerViewModel)
                
                // Status and feedback UI
                VStack {
                    Spacer()

                    // Status bar
                    StatusBarView(scannerViewModel: scannerViewModel)

                    // Manual zoom slider
                    HStack(spacing: 12) {
                        // Show the smoothed/displayed zoom value so UI matches the ramp animation
                        Text(String(format: "%.2fx", scannerViewModel.displayedZoom))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.leading, 6)

                        // Bind the slider thumb to a local sliderValue so dragging is responsive and we can commit
                        // the final value to the camera when editing ends. While dragging we update the smoothing
                        // target so the smoothed displayedZoom follows the user input.
                        Slider(value: Binding(get: {
                             // Show local slider value while dragging; initialize from displayedZoom on appear
                             sliderValue
                         }, set: { newVal in
                             sliderValue = newVal
                             // Update smoothing target immediately so the thumb and label feel responsive
                             scannerViewModel.setDisplayedZoomTarget(CGFloat(newVal))
                         }), in: Double(scannerViewModel.minSupportedZoom)...Double(scannerViewModel.maxSupportedZoom), step: 0.01, onEditingChanged: { editing in
+                            // Track editing state so external camera updates do not jump the thumb while dragging
+                            isSliderEditing = editing
                            if !editing {
                                // User finished interacting — request the camera to apply the zoom (animated ramp)
                                scannerViewModel.setZoomFactor(CGFloat(sliderValue))
                            }
                        })
                        .onAppear {
                            sliderValue = Double(scannerViewModel.displayedZoom)
                        }
+                        // When the displayedZoom updates (from camera ramp), update the slider if the user is not interacting
+                        .onChange(of: scannerViewModel.displayedZoom) { newVal in
+                            guard !isSliderEditing else { return }
+                            // Animate the thumb to follow the camera ramp smoothly
+                            withAnimation(.linear(duration: 0.12)) {
+                                sliderValue = Double(newVal)
+                            }
+                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 6)

                    // Accessory preset selector
                    AccessoryPresetSelectorView(
                        presetManager: scannerViewModel.accessoryPresetManager,
                        isExpanded: .constant(false),
                        onPresetChange: {
                            scannerViewModel.handleAccessoryPresetChange()
                        }
                    )
                    .padding(.horizontal)

                    // Control buttons
                    ControlButtonsView(scannerViewModel: scannerViewModel)
                }
                .padding()
            }
            .navigationTitle("Apple Serial Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Settings") {
                        showingSettings = true
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("History") {
                        showingHistory = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView()
        }
        .alert("Scan Result", isPresented: $scannerViewModel.showingResultAlert) {
            Button("OK") { }
        } message: {
            Text(scannerViewModel.resultMessage)
        }
        .alert("Validation Required", isPresented: $scannerViewModel.showValidationAlert) {
            Button("Submit") {
                scannerViewModel.handleValidationConfirmation(confirmed: true)
            }
            Button("Cancel", role: .cancel) {
                scannerViewModel.handleValidationConfirmation(confirmed: false)
            }
        } message: {
            Text(scannerViewModel.validationAlertMessage)
        }
        .onAppear {
            scannerViewModel.startScanning()
        }
        .onDisappear {
            scannerViewModel.stopScanning()
        }
    }
}

// MARK: - Scanner Overlay View
struct ScannerOverlayView: View {
    @ObservedObject var scannerViewModel: SerialScannerViewModel
    @State private var roiRect: CGRect = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // White mask that hides the camera except the ROI (using even-odd fill)
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geometry.size))

                    // Auto square ROI (centered) based on accessory preset
                    let roiSize = scannerViewModel.accessoryPresetManager.currentOCRSettings.roiSize
                    let side = min(geometry.size.width, geometry.size.height) * roiSize.width
                    let roi = CGRect(
                        x: (geometry.size.width - side) / 2.0,
                        y: (geometry.size.height - side) / 2.0,
                        width: side,
                        height: side
                    )

                    path.addRoundedRect(in: roi, cornerSize: CGSize(width: 12, height: 12))
                }
                .fill(Color.white, style: FillStyle(eoFill: true))
                .ignoresSafeArea()

                // Recompute roi for layout and region updates
                let roiSize = scannerViewModel.accessoryPresetManager.currentOCRSettings.roiSize
                let side = min(geometry.size.width, geometry.size.height) * roiSize.width
                let roi = CGRect(
                    x: (geometry.size.width - side) / 2.0,
                    y: (geometry.size.height - side) / 2.0,
                    width: side,
                    height: side
                )
                Color.clear
                    .onAppear {
                        roiRect = roi
                        scannerViewModel.updateRegionOfInterest(from: roi, in: CGRect(origin: .zero, size: geometry.size))
                    }
                    .onChange(of: geometry.size) { _ in
                        let roiSize = scannerViewModel.accessoryPresetManager.currentOCRSettings.roiSize
                        let updatedSide = min(geometry.size.width, geometry.size.height) * roiSize.width
                        let updated = CGRect(
                            x: (geometry.size.width - updatedSide) / 2.0,
                            y: (geometry.size.height - updatedSide) / 2.0,
                            width: updatedSide,
                            height: updatedSide
                        )
                        roiRect = updated
                        scannerViewModel.updateRegionOfInterest(from: updated, in: CGRect(origin: .zero, size: geometry.size))
                    }
                // ROI stroke contrasts with white UI
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.black, lineWidth: 3)
                    .frame(width: roi.width, height: roi.height)
                    .position(x: roi.midX, y: roi.midY)
                
                // Corner indicators
                CornerIndicator(position: .topLeft)
                    .position(x: roi.minX + 20, y: roi.minY + 20)
                CornerIndicator(position: .topRight)
                    .position(x: roi.maxX - 20, y: roi.minY + 20)
                CornerIndicator(position: .bottomLeft)
                    .position(x: roi.minX + 20, y: roi.maxY - 20)
                CornerIndicator(position: .bottomRight)
                    .position(x: roi.maxX - 20, y: roi.maxY - 20)
                
                // Guidance text
                VStack {
                    Spacer()
                    
                    Text(scannerViewModel.guidanceText)
                        .foregroundColor(.black)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(Color.white.opacity(0.9))
                        .cornerRadius(8)
                        .padding(.bottom, 100)
                }
            }
        }
    }
}

// MARK: - Corner Indicator
struct CornerIndicator: View {
    enum Position {
        case topLeft, topRight, bottomLeft, bottomRight
    }
    
    let position: Position
    let size: CGFloat = 30
    let thickness: CGFloat = 4
    
    var body: some View {
        Path { path in
            switch position {
            case .topLeft:
                path.move(to: CGPoint(x: 0, y: thickness))
                path.addLine(to: CGPoint(x: 0, y: size))
                path.move(to: CGPoint(x: thickness, y: 0))
                path.addLine(to: CGPoint(x: size, y: 0))
            case .topRight:
                path.move(to: CGPoint(x: size - thickness, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.move(to: CGPoint(x: size, y: thickness))
                path.addLine(to: CGPoint(x: size, y: size))
            case .bottomLeft:
                path.move(to: CGPoint(x: 0, y: size - thickness))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.move(to: CGPoint(x: thickness, y: size))
                path.addLine(to: CGPoint(x: size, y: size))
            case .bottomRight:
                path.move(to: CGPoint(x: 0, y: size))
                path.addLine(to: CGPoint(x: size - thickness, y: size))
                path.move(to: CGPoint(x: size, y: 0))
                path.addLine(to: CGPoint(x: size, y: size - thickness))
            }
        }
        .stroke(Color.black, lineWidth: 4)
        .frame(width: 30, height: 30)
    }
}

// MARK: - Status Bar View
struct StatusBarView: View {
    @ObservedObject var scannerViewModel: SerialScannerViewModel

    var body: some View {
        VStack(spacing: 8) {
            // Top row: Device type and frame counter
            HStack {
                // Device type indicator (platform)
                HStack {
                    #if os(iOS)
                    Image(systemName: "iphone")
                    #else
                    Image(systemName: "macbook")
                    #endif
                    Text(scannerViewModel.deviceType)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.8))
                .cornerRadius(20)

                Spacer()

                // Accessory preset indicator
                HStack {
                    Image(systemName: scannerViewModel.accessoryPresetManager.selectedAccessoryType.iconName)
                        .font(.system(size: 14))
                    Text(scannerViewModel.accessoryPresetManager.selectedAccessoryType.rawValue)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.8))
                .cornerRadius(20)

                Spacer()

                // Confidence indicator
                if scannerViewModel.bestConfidence > 0 {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("\(Int(scannerViewModel.bestConfidence * 100))%")
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.8))
                    .cornerRadius(20)
                }

                Spacer()

                // Frame counter
                HStack {
                    Image(systemName: "camera.fill")
                    Text("\(scannerViewModel.processedFrames)/\(scannerViewModel.maxFrames)")
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.8))
                .cornerRadius(20)
            }

            // Bottom row: Detection indicators
            HStack(spacing: 12) {
                if scannerViewModel.isSurfaceDetectionEnabled {
                    SurfaceIndicatorView(viewModel: scannerViewModel)
                        .transition(.opacity)
                }

                if scannerViewModel.isLightingDetectionEnabled {
                    LightingIndicatorView(viewModel: scannerViewModel)
                        .transition(.opacity)
                }

                if scannerViewModel.isAngleDetectionEnabled {
                    AngleIndicatorView(viewModel: scannerViewModel)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Control Buttons View
struct ControlButtonsView: View {
    @ObservedObject var scannerViewModel: SerialScannerViewModel

    var body: some View {
        VStack(spacing: 20) {
            // Detection toggles
            HStack(spacing: 12) {
                // Surface detection toggle
                Button(action: {
                    scannerViewModel.toggleSurfaceDetection()
                }) {
                    HStack {
                        Image(systemName: scannerViewModel.isSurfaceDetectionEnabled ? "eye.fill" : "eye.slash")
                            .font(.system(size: 16))
                        Text(scannerViewModel.isSurfaceDetectionEnabled ? "Surface ON" : "Surface OFF")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(scannerViewModel.isSurfaceDetectionEnabled ? Color.green.opacity(0.8) : Color.gray.opacity(0.6))
                    )
                }

                // Lighting detection toggle
                Button(action: {
                    scannerViewModel.toggleLightingDetection()
                }) {
                    HStack {
                        Image(systemName: scannerViewModel.isLightingDetectionEnabled ? "sun.max.fill" : "sun.max")
                            .font(.system(size: 16))
                        Text(scannerViewModel.isLightingDetectionEnabled ? "Lighting ON" : "Lighting OFF")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(scannerViewModel.isLightingDetectionEnabled ? Color.orange.opacity(0.8) : Color.gray.opacity(0.6))
                    )
                }

                // Angle detection toggle
                Button(action: {
                    scannerViewModel.toggleAngleDetection()
                }) {
                    HStack {
                        Image(systemName: scannerViewModel.isAngleDetectionEnabled ? "angle" : "angle")
                            .font(.system(size: 16))
                        Text(scannerViewModel.isAngleDetectionEnabled ? "Angle ON" : "Angle OFF")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(scannerViewModel.isAngleDetectionEnabled ? Color.purple.opacity(0.8) : Color.gray.opacity(0.6))
                    )
                }
            }

            // Main control buttons
            HStack(spacing: 30) {
                // Manual capture button
                Button(action: {
                    scannerViewModel.manualCapture()
                }) {
                    Image(systemName: "camera.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                }
                .disabled(scannerViewModel.isProcessing)

                #if os(iOS)
                // Flash toggle (iOS only)
                Button(action: {
                    scannerViewModel.toggleFlash()
                }) {
                    Image(systemName: scannerViewModel.isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                #endif
            }
        }
        .padding(.bottom, 50)
    }
}

// MARK: - Preview
struct SerialScannerView_Previews: PreviewProvider {
    static var previews: some View {
        SerialScannerView(scannerViewModel: SerialScannerViewModel())
    }
}
