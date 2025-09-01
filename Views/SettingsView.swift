import SwiftUI

struct SettingsView: View {
    @State private var baseURL = UserDefaults.standard.string(forKey: "backend_base_url") ?? "http://localhost:8000"
    @State private var apiKey = UserDefaults.standard.string(forKey: "backend_api_key") ?? ""
    @State private var selectedPreset = UserDefaults.standard.string(forKey: "selected_preset") ?? "default"
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isTestingConnection = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    
    @Environment(\.dismiss) private var dismiss
    
    private let backendService = BackendService()
    
    enum ConnectionStatus {
        case unknown, connected, failed
        
        var color: Color {
            switch self {
            case .unknown: return .gray
            case .connected: return .green
            case .failed: return .red
            }
        }
        
        var text: String {
            switch self {
            case .unknown: return "Unknown"
            case .connected: return "Connected"
            case .failed: return "Failed"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Backend Configuration")) {
                    HStack {
                        Text("Base URL")
                        Spacer()
                        TextField("http://localhost:8000", text: $baseURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 200)
                    }
                    
                    HStack {
                        Text("API Key")
                        Spacer()
                        SecureField("Optional", text: $apiKey)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 200)
                    }
                    
                    HStack {
                        Text("Connection Status")
                        Spacer()
                        HStack {
                            Circle()
                                .fill(connectionStatus.color)
                                .frame(width: 10, height: 10)
                            Text(connectionStatus.text)
                                .foregroundColor(connectionStatus.color)
                        }
                    }
                    
                    Button(action: testConnection) {
                        HStack {
                            if isTestingConnection {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "network")
                            }
                            Text("Test Connection")
                        }
                    }
                    .disabled(isTestingConnection)
                }
                
                Section(header: Text("Scanning Configuration")) {
                    Picker("Preset", selection: $selectedPreset) {
                        Text("Default").tag("default")
                        Text("Accessory").tag("accessory")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    if selectedPreset == "accessory" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Accessory Preset")
                                .font(.headline)
                            Text("Optimized for small accessory serial numbers with expanded ROI and lower text height threshold.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Default Preset")
                                .font(.headline)
                            Text("Standard settings for typical Apple device serial numbers.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section(header: Text("Device Information")) {
                    HStack {
                        Text("Device Type")
                        Spacer()
                        Text(PlatformDetector.deviceName)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Platform")
                        Spacer()
                        Text(PlatformDetector.current == .iOS ? "iOS" : "macOS")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("System Version")
                        Spacer()
                        Text(PlatformDetector.systemVersion)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Actions")) {
                    Button("Reset to Defaults") {
                        resetToDefaults()
                    }
                    .foregroundColor(.orange)
                    
                    Button("Clear All Data") {
                        clearAllData()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveSettings()
                    }
                }
            }
        }
        .alert("Settings", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            loadSettings()
        }
    }
    
    // MARK: - Actions
    private func testConnection() {
        isTestingConnection = true
        connectionStatus = .unknown
        
        Task {
            do {
                let isConnected = try await backendService.healthCheck()
                await MainActor.run {
                    connectionStatus = isConnected ? .connected : .failed
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    connectionStatus = .failed
                    isTestingConnection = false
                }
            }
        }
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(baseURL, forKey: "backend_base_url")
        UserDefaults.standard.set(apiKey, forKey: "backend_api_key")
        UserDefaults.standard.set(selectedPreset, forKey: "selected_preset")
        
        alertMessage = "Settings saved successfully"
        showingAlert = true
        
        // Test connection after saving
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            testConnection()
        }
    }
    
    private func loadSettings() {
        baseURL = UserDefaults.standard.string(forKey: "backend_base_url") ?? "http://localhost:8000"
        apiKey = UserDefaults.standard.string(forKey: "backend_api_key") ?? ""
        selectedPreset = UserDefaults.standard.string(forKey: "selected_preset") ?? "default"
    }
    
    private func resetToDefaults() {
        baseURL = "http://localhost:8000"
        apiKey = ""
        selectedPreset = "default"
        
        alertMessage = "Settings reset to defaults"
        showingAlert = true
    }
    
    private func clearAllData() {
        // Clear UserDefaults
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        
        alertMessage = "All data cleared"
        showingAlert = true
        
        // Reload settings
        loadSettings()
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
