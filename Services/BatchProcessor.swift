import SwiftUI
import Combine

@MainActor
class BatchProcessor: ObservableObject {
    // MARK: - Published Properties
    @Published var currentSession: BatchSession?
    @Published var isProcessing = false
    @Published var currentItem: BatchItem?
    @Published var progress: Double = 0.0
    @Published var estimatedTimeRemaining: TimeInterval = 0.0
    @Published var processingStartTime: Date?

    // MARK: - Private Properties
    private var autoAdvanceTimer: Timer?
    private var sessionTimeoutTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private weak var scannerViewModel: SerialScannerViewModel?

    // MARK: - Statistics
    private var itemStartTimes: [UUID: Date] = [:]
    private var itemProcessingTimes: [UUID: TimeInterval] = [:]

    init(scannerViewModel: SerialScannerViewModel) {
        self.scannerViewModel = scannerViewModel
        setupBindings()
    }

    private func setupBindings() {
        // Observe scanner results for batch processing
        scannerViewModel.$validationResult
            .sink { [weak self] validationResult in
                if let result = validationResult, self?.isProcessing == true {
                    self?.handleValidationResult(result)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Session Management
    func createBatchSession(name: String, deviceTypes: [AccessoryType], settings: BatchSettings = .default) -> BatchSession {
        let items = deviceTypes.map { BatchItem(deviceType: $0) }
        return BatchSession(
            id: UUID(),
            name: name,
            createdAt: Date(),
            items: items,
            currentIndex: 0,
            status: .pending,
            settings: settings
        )
    }

    func startBatchSession(_ session: BatchSession) {
        var session = session
        session.status = .inProgress
        session.currentIndex = 0

        self.currentSession = session
        self.isProcessing = true
        self.processingStartTime = Date()
        self.progress = 0.0

        // Save session
        if session.settings.saveProgress {
            BatchSession.saveSession(session)
        }

        // Start processing first item
        processNextItem()

        // Set up session timeout
        setupSessionTimeout()
    }

    func pauseBatchSession() {
        guard var session = currentSession else { return }

        session.status = .paused
        currentSession = session
        isProcessing = false

        cancelTimers()
        saveCurrentSession()

        // Reset scanner to manual mode
        scannerViewModel.stopScanning()
    }

    func resumeBatchSession() {
        guard var session = currentSession, session.status == .paused else { return }

        session.status = .inProgress
        currentSession = session
        isProcessing = true

        // Save session
        if session.settings.saveProgress {
            BatchSession.saveSession(session)
        }

        // Restart scanning
        scannerViewModel.startScanning()

        // Continue with current item
        if let item = session.currentItem {
            prepareForItem(item)
        }

        // Reset session timeout
        setupSessionTimeout()
    }

    func cancelBatchSession() {
        guard var session = currentSession else { return }

        session.status = .cancelled
        session.completedAt = Date()
        currentSession = nil
        isProcessing = false

        cancelTimers()
        saveCurrentSession()

        // Reset scanner
        scannerViewModel.stopScanning()
        scannerViewModel.updateGuidanceText("Batch session cancelled")
    }

    // MARK: - Item Processing
    private func processNextItem() {
        guard var session = currentSession, !session.isComplete else {
            completeBatchSession()
            return
        }

        guard let item = session.currentItem else {
            completeBatchSession()
            return
        }

        currentItem = item
        session.items[session.currentIndex].status = .processing

        // Record start time for statistics
        itemStartTimes[item.id] = Date()

        // Update session
        currentSession = session

        // Save progress
        if session.settings.saveProgress {
            BatchSession.saveSession(session)
        }

        // Prepare scanner for this item
        prepareForItem(item)

        // Update progress
        updateProgress()
    }

    private func prepareForItem(_ item: BatchItem) {
        // Set accessory preset for this device type
        scannerViewModel.accessoryPresetManager.selectedAccessoryType = item.deviceType

        // Apply preset settings
        scannerViewModel.handleAccessoryPresetChange()

        // Update guidance text
        let deviceName = item.deviceType.description
        scannerViewModel.updateGuidanceText("Scanning \(deviceName) (Item \(currentSession?.currentIndex ?? 0 + 1) of \(currentSession?.items.count ?? 0))")

        // Start scanning
        scannerViewModel.startScanning()
    }

    private func handleValidationResult(_ validationResult: ValidationResult) {
        guard var session = currentSession,
              var item = currentItem,
              item.id == session.items[session.currentIndex].id else { return }

        switch validationResult.level {
        case .ACCEPT:
            // Success - update item and move to next
            session.updateItemStatus(
                itemId: item.id,
                status: .completed,
                serial: validationResult.serial,
                confidence: validationResult.confidence
            )

            // Record processing time
            if let startTime = itemStartTimes[item.id] {
                let processingTime = Date().timeIntervalSince(startTime)
                itemProcessingTimes[item.id] = processingTime
            }

            currentSession = session

            if session.settings.autoAdvance {
                scheduleAutoAdvance()
            } else {
                // Wait for manual confirmation
                scannerViewModel.updateGuidanceText("Serial captured! Tap 'Next' to continue or 'Complete' to finish.")
            }

        case .BORDERLINE:
            // Handle borderline results based on settings
            if session.settings.retryFailedItems && item.retryCount < session.settings.maxRetries {
                // Retry with modified settings
                retryItem(&item, &session)
            } else {
                // Accept borderline result
                session.updateItemStatus(
                    itemId: item.id,
                    status: .completed,
                    serial: validationResult.serial,
                    confidence: validationResult.confidence
                )
                currentSession = session
                scheduleAutoAdvance()
            }

        case .REJECT:
            // Handle rejection
            if session.settings.retryFailedItems && item.retryCount < session.settings.maxRetries {
                retryItem(&item, &session)
            } else {
                // Mark as failed
                session.updateItemStatus(
                    itemId: item.id,
                    status: .failed,
                    errorMessage: "Validation failed - invalid serial format"
                )
                currentSession = session
                handleItemFailure()
            }
        }
    }

    private func retryItem(_ item: inout BatchItem, _ session: inout BatchSession) {
        item.retryCount += 1

        // Modify settings for retry (e.g., longer processing time, different preset)
        if item.retryCount == 1 {
            // First retry: extend processing window
            scannerViewModel.updateGuidanceText("Retrying with extended processing time...")
        } else if item.retryCount == 2 {
            // Second retry: try alternative preset
            let alternativePreset = getAlternativePreset(for: item.deviceType)
            scannerViewModel.accessoryPresetManager.selectedAccessoryType = alternativePreset
            scannerViewModel.handleAccessoryPresetChange()
            scannerViewModel.updateGuidanceText("Retrying with alternative settings...")
        }

        // Restart scanning for this item
        scannerViewModel.stopScanning()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.scannerViewModel.startScanning()
        }
    }

    private func getAlternativePreset(for deviceType: AccessoryType) -> AccessoryType {
        // Provide alternative presets for retry attempts
        switch deviceType {
        case .iphone: return .accessory // More flexible settings
        case .ipad: return .accessory
        case .macbook: return .accessory
        case .appleWatch: return .accessory
        default: return .auto
        }
    }

    private func handleItemFailure() {
        guard var session = currentSession else { return }

        // Move to next item after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            session.moveToNextItem()
            self.currentSession = session
            self.processNextItem()
        }
    }

    private func scheduleAutoAdvance() {
        guard let session = currentSession, session.settings.autoAdvance else { return }

        autoAdvanceTimer?.invalidate()
        autoAdvanceTimer = Timer.scheduledTimer(withTimeInterval: session.settings.autoAdvanceDelay, repeats: false) { [weak self] _ in
            self?.advanceToNextItem()
        }
    }

    func advanceToNextItem() {
        guard var session = currentSession else { return }

        cancelTimers()
        session.moveToNextItem()
        currentSession = session

        if session.isComplete {
            completeBatchSession()
        } else {
            processNextItem()
        }
    }

    private func completeBatchSession() {
        guard var session = currentSession else { return }

        session.status = .completed
        session.completedAt = Date()
        currentSession = session
        isProcessing = false

        cancelTimers()

        // Save final session
        if session.settings.saveProgress {
            BatchSession.saveSession(session)
        }

        // Export if requested
        if session.settings.exportOnComplete {
            exportBatchResults(session)
        }

        // Update UI
        scannerViewModel.updateGuidanceText("Batch session completed! \(session.completedItems) of \(session.items.count) items scanned successfully.")

        // Generate completion statistics
        let statistics = generateStatistics(for: session)
        print("Batch completed: \(statistics.completionRate * 100)% success rate")
    }

    // MARK: - Utility Methods
    private func updateProgress() {
        guard let session = currentSession else { return }
        progress = session.progress

        // Estimate remaining time
        if let startTime = processingStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            let remainingItems = session.items.count - session.completedItems
            if session.completedItems > 0 {
                let avgTimePerItem = elapsed / Double(session.completedItems)
                estimatedTimeRemaining = avgTimePerItem * Double(remainingItems)
            }
        }
    }

    private func setupSessionTimeout() {
        guard let session = currentSession else { return }

        sessionTimeoutTimer?.invalidate()
        sessionTimeoutTimer = Timer.scheduledTimer(withTimeInterval: session.settings.sessionTimeout, repeats: false) { [weak self] _ in
            self?.handleSessionTimeout()
        }
    }

    private func handleSessionTimeout() {
        pauseBatchSession()
        scannerViewModel.updateGuidanceText("Batch session paused due to inactivity. Resume when ready.")
    }

    private func cancelTimers() {
        autoAdvanceTimer?.invalidate()
        autoAdvanceTimer = nil
        sessionTimeoutTimer?.invalidate()
        sessionTimeoutTimer = nil
    }

    private func saveCurrentSession() {
        guard let session = currentSession, session.settings.saveProgress else { return }
        BatchSession.saveSession(session)
    }

    private func exportBatchResults(_ session: BatchSession) {
        // Implementation for exporting batch results
        // This will be expanded in Phase 3.0
        print("Exporting batch results for session: \(session.name)")
    }

    private func generateStatistics(for session: BatchSession) -> BatchStatistics {
        let totalItems = session.items.count
        let completedItems = session.completedItems
        let failedItems = session.failedItems
        let skippedItems = session.items.filter { $0.status == .skipped }.count

        let confidences = session.items.compactMap { $0.confidence }
        let averageConfidence = confidences.isEmpty ? 0.0 : confidences.reduce(0, +) / Float(confidences.count)

        let processingTimes = itemProcessingTimes.values
        let averageProcessingTime = processingTimes.isEmpty ? 0.0 : processingTimes.reduce(0, +) / Double(processingTimes.count)

        return BatchStatistics(
            totalItems: totalItems,
            completedItems: completedItems,
            failedItems: failedItems,
            skippedItems: skippedItems,
            averageConfidence: averageConfidence,
            averageProcessingTime: averageProcessingTime,
            startTime: session.createdAt,
            endTime: session.completedAt
        )
    }

    // MARK: - Public Methods
    func skipCurrentItem() {
        guard var session = currentSession,
              let item = currentItem else { return }

        session.updateItemStatus(itemId: item.id, status: .skipped)
        currentSession = session

        advanceToNextItem()
    }

    func retryCurrentItem() {
        guard var session = currentSession,
              var item = currentItem else { return }

        item.retryCount = 0 // Reset retry count
        session.items[session.currentIndex] = item
        currentSession = session

        // Restart processing for this item
        prepareForItem(item)
    }
}
