import SwiftUI
import Vision
import VisionKit
import AVFoundation
import Combine

struct IPadOptimizedSerialScannerView: View {
    @ObservedObject var scannerViewModel: SerialScannerViewModel
    @State private var showingSettings = false
    @State private var showingHistory = false
    @State private var showFlashButton = false
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        NavigationView {
            ZStack {
                // Camera preview with overlay
                CameraPreviewView(previewLayer: scannerViewModel.previewLayer)
                    .ignoresSafeArea()
                
                // Clean rectangular scanner overlay
                CleanScannerOverlayView(viewModel: scannerViewModel)
                
                // Bottom toolbar with minimal controls
                VStack {
                    Spacer()
                    
                    // Minimal control buttons - only what's needed
                    HStack(spacing: 40) {
                        // Flash toggle button
                        if showFlashButton {
                            Button(action: {
                                scannerViewModel.toggleFlash()
                            }) {
                                Image(systemName: scannerViewModel.isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .frame(width: 60, height: 60)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                            }
                        }
                        
                        // Capture button - enlarged for iPad
                        Button(action: {
                            scannerViewModel.startAutoCapture()
                        }) {
                            Circle()
                                .stroke(Color.white, lineWidth: 5)
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 70, height: 70)
                                )
                        }
                        
                        // Settings button
                        Button(action: {
                            scannerViewModel.showingPresetSelector = true
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.bottom, horizontalSizeClass == .regular ? 50 : 30)
                }
            }
            .sheet(isPresented: $scannerViewModel.showingPresetSelector) {
                AccessoryPresetSelectorView(
                    presetManager: scannerViewModel.accessoryPresetManager,
                    isExpanded: .constant(true),
                    onPresetChange: {
                        scannerViewModel.handleAccessoryPresetChange()
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .navigationTitle("Apple Serial Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingHistory = true
                    }) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
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
            // Check if device has flash
            #if os(iOS)
            showFlashButton = AVCaptureDevice.default(for: .video)?.hasTorch ?? false
            #endif
        }
        .onDisappear {
            scannerViewModel.stopScanning()
        }
    }
}
