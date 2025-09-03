import SwiftUI

struct BatchProcessingView: View {
    @StateObject private var batchProcessor: BatchProcessor
    @State private var showingCreateSession = false
    @State private var selectedSession: BatchSession?

    init(scannerViewModel: SerialScannerViewModel) {
        _batchProcessor = StateObject(wrappedValue: scannerViewModel.batchProcessor)
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if batchProcessor.currentSession != nil {
                    // Active session view
                    ActiveBatchSessionView(batchProcessor: batchProcessor)
                } else {
                    // Session list view
                    BatchSessionListView(
                        batchProcessor: batchProcessor,
                        showingCreateSession: $showingCreateSession
                    )
                }
            }
            .navigationTitle("Batch Processing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if batchProcessor.currentSession == nil {
                        Button(action: {
                            showingCreateSession = true
                        }) {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingCreateSession) {
            CreateBatchSessionView(batchProcessor: batchProcessor)
        }
        .onAppear {
            // Load saved sessions
            loadSavedSessions()
        }
    }

    private func loadSavedSessions() {
        // Sessions are loaded automatically by BatchSession.loadSessions()
        // This method can be used for any additional setup
    }
}

// MARK: - Active Batch Session View
struct ActiveBatchSessionView: View {
    @ObservedObject var batchProcessor: BatchProcessor
    @State private var showingPauseAlert = false

    var body: some View {
        VStack(spacing: 20) {
            // Session header
            if let session = batchProcessor.currentSession {
                BatchSessionHeader(session: session)
            }

            // Progress indicator
            BatchProgressView(batchProcessor: batchProcessor)

            // Current item display
            if let currentItem = batchProcessor.currentItem {
                CurrentBatchItemView(item: currentItem, batchProcessor: batchProcessor)
            }

            // Control buttons
            BatchControlButtons(batchProcessor: batchProcessor, showingPauseAlert: $showingPauseAlert)

            Spacer()
        }
        .padding()
        .alert("Pause Batch Session", isPresented: $showingPauseAlert) {
            Button("Pause", role: .destructive) {
                batchProcessor.pauseBatchSession()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will pause the current batch session. You can resume it later.")
        }
    }
}

// MARK: - Batch Progress View
struct BatchProgressView: View {
    @ObservedObject var batchProcessor: BatchProcessor

    var body: some View {
        VStack(spacing: 12) {
            // Circular progress
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: batchProcessor.progress)
                    .stroke(Color.blue, lineWidth: 8)
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))

                VStack {
                    Text("\(Int(batchProcessor.progress * 100))%")
                        .font(.title2)
                        .fontWeight(.bold)

                    if let session = batchProcessor.currentSession {
                        Text("\(session.completedItems)/\(session.items.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Time estimate
            if batchProcessor.estimatedTimeRemaining > 0 {
                Text("Estimated time: \(formatTime(batchProcessor.estimatedTimeRemaining))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Status text
            if let session = batchProcessor.currentSession {
                Text(session.status.rawValue)
                    .font(.headline)
                    .foregroundColor(statusColor(for: session.status))
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4)
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func statusColor(for status: BatchStatus) -> Color {
        switch status {
        case .inProgress: return .blue
        case .paused: return .orange
        case .completed: return .green
        case .cancelled: return .red
        case .pending: return .gray
        }
    }
}

// MARK: - Current Batch Item View
struct CurrentBatchItemView: View {
    let item: BatchItem
    @ObservedObject var batchProcessor: BatchProcessor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: item.deviceType.iconName)
                    .font(.title2)
                    .foregroundColor(.blue)

                VStack(alignment: .leading) {
                    Text(item.deviceType.description)
                        .font(.headline)

                    Text(item.deviceType.serialFormat)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Status indicator
                StatusIndicator(status: item.status)
            }

            if let serial = item.serialNumber {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Serial Number:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(serial)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(6)

                    if let confidence = item.confidence {
                        Text("Confidence: \(Int(confidence * 100))%")
                            .font(.caption)
                            .foregroundColor(confidenceColor(confidence))
                    }
                }
            }

            if let errorMessage = item.errorMessage {
                Text("Error: \(errorMessage)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4)
    }

    private func confidenceColor(_ confidence: Float) -> Color {
        if confidence >= 0.8 { return .green }
        else if confidence >= 0.6 { return .orange }
        else { return .red }
    }
}

// MARK: - Status Indicator
struct StatusIndicator: View {
    let status: BatchItemStatus

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)

            Text(status.rawValue)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var statusColor: Color {
        switch status {
        case .completed: return .green
        case .processing: return .blue
        case .failed: return .red
        case .pending: return .gray
        case .skipped: return .orange
        }
    }
}

// MARK: - Batch Control Buttons
struct BatchControlButtons: View {
    @ObservedObject var batchProcessor: BatchProcessor
    @Binding var showingPauseAlert: Bool

    var body: some View {
        HStack(spacing: 16) {
            if batchProcessor.isProcessing {
                // Pause button
                Button(action: {
                    showingPauseAlert = true
                }) {
                    HStack {
                        Image(systemName: "pause.fill")
                        Text("Pause")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }

                // Skip button
                Button(action: {
                    batchProcessor.skipCurrentItem()
                }) {
                    HStack {
                        Image(systemName: "arrow.right")
                        Text("Skip")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            } else {
                // Resume button
                Button(action: {
                    batchProcessor.resumeBatchSession()
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Resume")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }

                // Cancel button
                Button(action: {
                    batchProcessor.cancelBatchSession()
                }) {
                    HStack {
                        Image(systemName: "xmark")
                        Text("Cancel")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
        }
    }
}

// MARK: - Batch Session Header
struct BatchSessionHeader: View {
    let session: BatchSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.name)
                .font(.title2)
                .fontWeight(.bold)

            HStack {
                Text("Created: \(formatDate(session.createdAt))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(session.items.count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Batch Session List View
struct BatchSessionListView: View {
    @ObservedObject var batchProcessor: BatchProcessor
    @Binding var showingCreateSession: Bool
    @State private var savedSessions: [BatchSession] = []

    var body: some View {
        VStack {
            if savedSessions.isEmpty {
                // Empty state
                VStack(spacing: 20) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 64))
                        .foregroundColor(.gray)

                    Text("No Batch Sessions")
                        .font(.title2)
                        .foregroundColor(.gray)

                    Text("Create your first batch processing session to scan multiple devices efficiently.")
                        .font(.body)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button(action: {
                        showingCreateSession = true
                    }) {
                        Text("Create Session")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                }
                .padding()
            } else {
                // Session list
                List(savedSessions) { session in
                    BatchSessionRow(session: session, batchProcessor: batchProcessor)
                }
                .listStyle(InsetGroupedListStyle())
            }
        }
        .onAppear {
            loadSessions()
        }
    }

    private func loadSessions() {
        savedSessions = BatchSession.loadSessions()
    }
}

// MARK: - Batch Session Row
struct BatchSessionRow: View {
    let session: BatchSession
    @ObservedObject var batchProcessor: BatchProcessor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(session.name)
                        .font(.headline)

                    Text("Created: \(formatDate(session.createdAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text(session.status.rawValue)
                        .font(.caption)
                        .foregroundColor(statusColor)

                    Text("\(session.completedItems)/\(session.items.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)
                        .cornerRadius(2)

                    Rectangle()
                        .fill(statusColor)
                        .frame(width: geometry.size.width * session.progress, height: 4)
                        .cornerRadius(2)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            // Handle session selection
            batchProcessor.currentSession = session
            if session.status == .paused {
                // Optionally auto-resume
            }
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .completed: return .green
        case .inProgress: return .blue
        case .paused: return .orange
        case .cancelled: return .red
        case .pending: return .gray
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Create Batch Session View
struct CreateBatchSessionView: View {
    @ObservedObject var batchProcessor: BatchProcessor
    @Environment(\.dismiss) var dismiss

    @State private var sessionName = ""
    @State private var selectedDeviceTypes: [AccessoryType] = []
    @State private var deviceQuantities: [AccessoryType: Int] = [:]

    let availableDevices: [AccessoryType] = [
        .iphone, .ipad, .macbook, .imac, .appleWatch,
        .airPods, .accessory
    ]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Session Details")) {
                    TextField("Session Name", text: $sessionName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                Section(header: Text("Select Devices")) {
                    ForEach(availableDevices, id: \.self) { deviceType in
                        HStack {
                            Image(systemName: deviceType.iconName)
                                .foregroundColor(.blue)
                                .frame(width: 24)

                            Text(deviceType.description)
                                .font(.body)

                            Spacer()

                            Stepper(
                                value: Binding(
                                    get: { deviceQuantities[deviceType] ?? 0 },
                                    set: { deviceQuantities[deviceType] = $0 }
                                ),
                                in: 0...20
                            ) {
                                Text("\(deviceQuantities[deviceType] ?? 0)")
                                    .font(.body)
                                    .frame(minWidth: 30)
                            }
                        }
                    }
                }

                Section {
                    Button(action: createSession) {
                        Text("Create Batch Session")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canCreateSession ? Color.blue : Color.gray)
                            .cornerRadius(10)
                    }
                    .disabled(!canCreateSession)
                }
            }
            .navigationTitle("Create Batch Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var canCreateSession: Bool {
        !sessionName.isEmpty && !deviceQuantities.filter { $0.value > 0 }.isEmpty
    }

    private func createSession() {
        var deviceList: [AccessoryType] = []

        for (deviceType, quantity) in deviceQuantities {
            for _ in 0..<quantity {
                deviceList.append(deviceType)
            }
        }

        let session = batchProcessor.createBatchSession(
            name: sessionName,
            deviceTypes: deviceList
        )

        batchProcessor.startBatchSession(session)
        dismiss()
    }
}

struct BatchProcessingView_Previews: PreviewProvider {
    static var previews: some View {
        BatchProcessingView(scannerViewModel: SerialScannerViewModel())
    }
}
