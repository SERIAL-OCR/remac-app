import SwiftUI
import AVFoundation

struct CleanIPadScannerView: View {
    @ObservedObject var viewModel: SerialScannerViewModel
    @State private var isScanning = false
    @State private var showFlashButton = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Camera preview 
            // Use SharedCameraView which accepts an optional AVCaptureVideoPreviewLayer
            SharedCameraView(previewLayer: viewModel.previewLayer)
                .ignoresSafeArea()
            
            // Scanner overlay with rectangular ROI
            RectangularScannerOverlay()
                .ignoresSafeArea()
            
            // Status text at the bottom
            VStack {
                Spacer()
                
                // Recognized text display
                if !viewModel.recognizedText.isEmpty {
                    Text(viewModel.recognizedText)
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(8)
                        .padding(.bottom, 8)
                }
                
                // Guidance text
                Text(viewModel.guidanceText)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                    .padding(.bottom, 20)
                
                // Controls
                HStack(spacing: 40) {
                    // Flash toggle button
                    if showFlashButton {
                        Button(action: {
                            viewModel.toggleFlash()
                        }) {
                            Image(systemName: viewModel.isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                    }
                    
                    // Scan button
                    Button(action: {
                        if isScanning {
                            viewModel.stopScanning()
                        } else {
                            viewModel.startScanning()
                            // Add a slight delay before starting auto capture to ensure camera is ready
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.startAutoCapture()
                            }
                        }
                        isScanning.toggle()
                    }) {
                        Image(systemName: isScanning ? "stop.fill" : "camera.viewfinder")
                            .font(.system(size: 36))
                            .foregroundColor(.white)
                            .frame(width: 80, height: 80)
                            .background(isScanning ? Color.red.opacity(0.8) : Color.blue.opacity(0.8))
                            .clipShape(Circle())
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            // Check if flash is available
            if let device = AVCaptureDevice.default(for: .video),
               device.hasTorch {
                showFlashButton = true
            }
        }
        .alert(isPresented: $viewModel.showingResultAlert) {
            Alert(
                title: Text("Scan Result"),
                message: Text(viewModel.resultMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(isPresented: $viewModel.showValidationAlert) {
            Alert(
                title: Text("Validation"),
                message: Text(viewModel.validationAlertMessage),
                primaryButton: .default(Text("Submit Anyway")) {
                    viewModel.handleValidationConfirmation(confirmed: true)
                },
                secondaryButton: .cancel(Text("Cancel")) {
                    viewModel.handleValidationConfirmation(confirmed: false)
                }
            )
        }
    }
    
    private func startAutoCapture() {
        // Create and execute a private method to invoke the auto capture
        // This is a workaround to access the private method in the view model
        let selectorName = "startAutoCapture"
        let selector = NSSelectorFromString(selectorName)
        if viewModel.responds(to: selector) {
            viewModel.perform(selector)
        }
    }
}

// Clean, minimal rectangular scanner overlay
struct RectangularScannerOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Semi-transparent overlay
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                    .edgesIgnoringSafeArea(.all)
                
                // Rectangular ROI for serial numbers (wider than tall)
                let roiWidth = min(geometry.size.width * 0.8, 600) // Limit max width on large iPads
                let roiHeight = roiWidth * 0.25 // 4:1 aspect ratio for serial numbers
                let roi = CGRect(
                    x: (geometry.size.width - roiWidth) / 2.0,
                    y: (geometry.size.height - roiHeight) / 2.0,
                    width: roiWidth,
                    height: roiHeight
                )
                
                // Create cutout in overlay
                Rectangle()
                    .path(in: roi)
                    .fill(Color.clear)
                    .blendMode(.destinationOut)
                
                // ROI corner brackets (Apple-style)
                CornerBrackets(rect: roi, color: .white, lineWidth: 3)
            }
            .compositingGroup()
        }
    }
}

// Corner brackets like those in Apple's scanner UI
struct CornerBrackets: View {
    let rect: CGRect
    let color: Color
    let lineWidth: CGFloat
    let bracketLength: CGFloat = 25
    
    var body: some View {
        ZStack {
            // Top-left corner
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.minY + bracketLength))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX + bracketLength, y: rect.minY))
            }
            .stroke(color, lineWidth: lineWidth)
            
            // Top-right corner
            Path { path in
                path.move(to: CGPoint(x: rect.maxX - bracketLength, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + bracketLength))
            }
            .stroke(color, lineWidth: lineWidth)
            
            // Bottom-right corner
            Path { path in
                path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - bracketLength))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX - bracketLength, y: rect.maxY))
            }
            .stroke(color, lineWidth: lineWidth)
            
            // Bottom-left corner
            Path { path in
                path.move(to: CGPoint(x: rect.minX + bracketLength, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bracketLength))
            }
            .stroke(color, lineWidth: lineWidth)
        }
    }
}

// Use shared CameraPreviewView from Shared directory instead of redefining it here
