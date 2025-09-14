import SwiftUI

/// Enhanced scanner settings view with accessibility options
struct ScannerSettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var feedbackManager: UIFeedbackManager
    @ObservedObject var accessibilityManager: AccessibilityManager
    
    @State private var showAdvancedSettings = false
    @State private var selectedTab = 0
    // Phase 9: Persisted scanner configurationK
    // Phase 9: Persisted scanner configuratio
    @AppStorage("scannerLanguages") private var scannerLanguagesString: String = "en-US,en"
    @AppStorage("scannerTextContentType") private var scannerTextContentTypeString: String = "generic"
    @AppStorage("stabilityThreshold") private var stabilityThreshold: Double = 0.8
    @AppStorage("enableBarcodeFallback") private var enableBarcodeFallback: Bool = true

    // Local state to remember previous values so telemetry captures diffs
    @State private var prevScannerLanguagesString: String = ""
    @State private var prevScannerTextContentTypeString: String = ""
    @State private var prevStabilityThresholdString: String = ""
    @State private var prevEnableBarcodeFallbackString: String = ""

    var body: some View {
        NavigationView {
            Form {
                // Phase 9: Scanner configuration
                Section(header: Text("Scanner Configuration")) {
                    VStack(alignment: .leading) {
                        Text("Recognition Languages (comma-separated)")
                        TextField("en-US,en", text: $scannerLanguagesString)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                    }
                    Picker("Text Content Type", selection: $scannerTextContentTypeString) {
                        Text("Generic").tag("generic")
                        Text("Email").tag("email")
                        Text("URL").tag("url")
                        Text("Phone").tag("phone")
                    }
                    Toggle("Enable Barcode Fallback", isOn: $enableBarcodeFallback)
                        .onChange(of: enableBarcodeFallback) { newValue in
                            TelemetryService.shared.trackSettingChange(
                                key: "enableBarcodeFallback",
                                oldValue: prevEnableBarcodeFallbackString,
                                newValue: String(newValue)
                            )
                            prevEnableBarcodeFallbackString = String(newValue)
                        }
                    VStack(alignment: .leading) {
                        Text("Stability Threshold: \(String(format: "%.2f", stabilityThreshold))")
                        Slider(value: $stabilityThreshold, in: 0.5...1.0, step: 0.01)
                            .onChange(of: stabilityThreshold) { newValue in
                                TelemetryService.shared.trackSettingChange(
                                    key: "stabilityThreshold",
                                    oldValue: prevStabilityThresholdString,
                                    newValue: String(format: "%.2f", newValue)
                                )
                                prevStabilityThresholdString = String(format: "%.2f", newValue)
                            }
                    }
                }
                // Visual Feedback Settings
                Section(header: Text("Visual Feedback")) {
                    Toggle("Show Stability Indicator", isOn: $feedbackManager.showStabilityIndicator)
                    Toggle("Show Quality Indicator", isOn: $feedbackManager.showQualityIndicator)
                    Toggle("Show Guidance Overlay", isOn: $feedbackManager.showGuidanceOverlay)
                    
                    ColorOpacityPicker(
                        "Overlay Opacity",
                        value: $feedbackManager.roiOverlayOpacity
                    )
                }
                
                // Accessibility Settings
                Section(header: Text("Accessibility")) {
                    Toggle("Voice Guidance", isOn: $accessibilityManager.isVoiceGuidanceEnabled)
                    Toggle("Haptic Feedback", isOn: $accessibilityManager.isHapticFeedbackEnabled)
                    Toggle("High Contrast Mode", isOn: $accessibilityManager.isHighContrastModeEnabled)
                }
                
                // Advanced Settings
                if showAdvancedSettings {
                    Section(header: Text("Advanced")) {
                        NavigationLink("ROI Configuration") {
                            ROIConfigurationView()
                        }
                        
                        NavigationLink("Feedback Timing") {
                            FeedbackTimingView()
                        }
                    }
                }
                
                Section {
                    Toggle("Show Advanced Settings", isOn: $showAdvancedSettings)
                }
            }
            .navigationTitle("Scanner Settings")
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .onAppear {
                // Initialize previous values for telemetry comparisons
                prevScannerLanguagesString = scannerLanguagesString
                prevScannerTextContentTypeString = scannerTextContentTypeString
                prevStabilityThresholdString = String(format: "%.2f", stabilityThreshold)
                prevEnableBarcodeFallbackString = String(enableBarcodeFallback)
            }
            .onChange(of: scannerLanguagesString) { newValue in
                TelemetryService.shared.trackSettingChange(
                    key: "scannerLanguages",
                    oldValue: prevScannerLanguagesString,
                    newValue: newValue
                )
                prevScannerLanguagesString = newValue
            }
            .onChange(of: scannerTextContentTypeString) { newValue in
                TelemetryService.shared.trackSettingChange(
                    key: "scannerTextContentType",
                    oldValue: prevScannerTextContentTypeString,
                    newValue: newValue
                )
                prevScannerTextContentTypeString = newValue
            }
        }
    }
}

/// Color opacity picker with preview
struct ColorOpacityPicker: View {
    let title: String
    @Binding var value: Double
    
    init(_ title: String, value: Binding<Double>) {
        self.title = title
        self._value = value
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
            
            HStack {
                Slider(value: $value, in: 0.1...1.0)
                
                // Preview
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(value))
                    .frame(width: 44, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary, lineWidth: 0.5)
                    )
            }
        }
    }
}

/// Feedback timing configuration
struct FeedbackTimingView: View {
    @AppStorage("feedbackDebounce") private var debounceInterval: Double = 0.5
    @AppStorage("guidanceDisplayTime") private var guidanceDisplayTime: Double = 3.0
    @AppStorage("successDisplayTime") private var successDisplayTime: Double = 2.0
    
    var body: some View {
        Form {
            Section(header: Text("Timing")) {
                VStack(alignment: .leading) {
                    Text("Feedback Delay")
                    Slider(value: $debounceInterval, in: 0.1...1.0)
                    Text(String(format: "%.1f seconds", debounceInterval))
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading) {
                    Text("Guidance Display Duration")
                    Slider(value: $guidanceDisplayTime, in: 1.0...5.0)
                    Text(String(format: "%.1f seconds", guidanceDisplayTime))
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading) {
                    Text("Success Animation Duration")
                    Slider(value: $successDisplayTime, in: 1.0...3.0)
                    Text(String(format: "%.1f seconds", successDisplayTime))
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Feedback Timing")
    }
}

// ROI configuration view is provided by Phase2ROIOverlayView (Phase2ROIOverlayView.swift).
// To avoid duplicate declarations we reuse that implementation where needed.
