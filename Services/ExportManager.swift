import SwiftUI
import Foundation
import UniformTypeIdentifiers

// MARK: - Export Manager
@MainActor
class ExportManager: ObservableObject {
    @Published var isExporting = false
    @Published var exportProgress: Double = 0.0
    @Published var currentExportTask: ExportTask?

    private let backendService = BackendService()
    private let googleSheetsService = GoogleSheetsService()
    private let numbersService = AppleNumbersService()
    private var exportTasks: [ExportTask] = []

    // MARK: - Export Formats
    enum ExportFormat {
        case excel
        case csv
        case json
        case googleSheets
        case appleNumbers
    }

    // MARK: - Export Task
    struct ExportTask {
        let id: UUID
        let format: ExportFormat
        let filename: String
        let timestamp: Date
        var status: ExportStatus
        var progress: Double
        var fileURL: URL?
        var errorMessage: String?

        init(format: ExportFormat, filename: String) {
            self.id = UUID()
            self.format = format
            self.filename = filename
            self.timestamp = Date()
            self.status = .pending
            self.progress = 0.0
        }
    }

    enum ExportStatus {
        case pending
        case inProgress
        case completed
        case failed
    }

    // MARK: - Export Methods

    func exportScanHistory(
        format: ExportFormat,
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        source: String? = nil,
        deviceType: String? = nil
    ) async throws -> URL {
        isExporting = true
        exportProgress = 0.0

        let task = ExportTask(
            format: format,
            filename: generateFilename(format: format)
        )

        currentExportTask = task
        exportTasks.append(task)

        do {
            // Update progress
            exportProgress = 0.1
            task.status = .inProgress

            // Fetch data from backend
            let data = try await fetchScanData(
                dateFrom: dateFrom,
                dateTo: dateTo,
                source: source,
                deviceType: deviceType
            )

            exportProgress = 0.3

            // Transform data based on format
            let transformedData = try await transformData(data, format: format)

            exportProgress = 0.7

            // Generate file
            let fileURL = try await generateFile(transformedData, format: format, filename: task.filename)

            exportProgress = 1.0
            task.status = .completed
            task.fileURL = fileURL

            isExporting = false
            return fileURL

        } catch {
            task.status = .failed
            task.errorMessage = error.localizedDescription
            isExporting = false
            throw error
        }
    }

    func exportBatchResults(_ session: BatchSession, formats: [ExportFormat] = [.excel, .csv]) async throws -> [URL] {
        isExporting = true
        exportProgress = 0.0

        var exportedFiles: [URL] = []
        let totalFormats = Double(formats.count)

        for (index, format) in formats.enumerated() {
            let task = ExportTask(
                format: format,
                filename: generateBatchFilename(session: session, format: format)
            )

            currentExportTask = task
            exportTasks.append(task)

            do {
                task.status = .inProgress

                // Transform batch data
                let transformedData = try await transformBatchData(session, format: format)

                exportProgress = (Double(index) + 0.7) / totalFormats

                // Generate file
                let fileURL = try await generateFile(transformedData, format: format, filename: task.filename)

                task.status = .completed
                task.fileURL = fileURL
                exportedFiles.append(fileURL)

            } catch {
                task.status = .failed
                task.errorMessage = error.localizedDescription
            }
        }

        exportProgress = 1.0
        isExporting = false
        return exportedFiles
    }

    // MARK: - Google Sheets Integration
    func exportToGoogleSheets(
        scanData: [ScanHistory],
        spreadsheetId: String? = nil
    ) async throws -> String {
        isExporting = true
        exportProgress = 0.0

        let task = ExportTask(
            format: .googleSheets,
            filename: "GoogleSheets_\(Date().formatted())"
        )

        currentExportTask = task

        do {
            task.status = .inProgress
            exportProgress = 0.2

            // Check authentication
            if !googleSheetsService.isAuthenticated {
                throw GoogleSheetsError.notAuthenticated
            }

            // Transform data for Google Sheets
            let sheetsData = try await transformForGoogleSheets(scanData)

            exportProgress = 0.5

            // Create or update Google Sheet
            let spreadsheetURL: String
            if let spreadsheetId = spreadsheetId {
                // Update existing spreadsheet
                if case .googleSheets(let values) = sheetsData {
                    try await googleSheetsService.updateSpreadsheet(
                        spreadsheetId: spreadsheetId,
                        values: values
                    )
                }
                let spreadsheet = try await googleSheetsService.getSpreadsheet(spreadsheetId: spreadsheetId)
                spreadsheetURL = spreadsheet.spreadsheetUrl
            } else {
                // Create new spreadsheet
                let title = "Apple Serial Scan - \(Date().formatted(date: .abbreviated, time: .omitted))"
                if case .googleSheets(let values) = sheetsData {
                    spreadsheetURL = try await googleSheetsService.createAndPopulateSpreadsheet(
                        title: title,
                        values: values
                    )
                } else {
                    throw ExportError.invalidDataFormat
                }
            }

            exportProgress = 1.0
            task.status = .completed

            isExporting = false
            return spreadsheetURL

        } catch {
            task.status = .failed
            task.errorMessage = error.localizedDescription
            isExporting = false
            throw error
        }
    }

    // MARK: - Apple Numbers Integration
    func exportToNumbers(
        scanData: [ScanHistory],
        template: NumbersTemplate? = nil
    ) async throws -> URL {
        isExporting = true
        exportProgress = 0.0

        let task = ExportTask(
            format: .appleNumbers,
            filename: generateFilename(format: .appleNumbers)
        )

        currentExportTask = task

        do {
            task.status = .inProgress
            exportProgress = 0.2

            // Export using Numbers service
            let fileURL = try await numbersService.exportScanHistory(
                title: "Apple Serial Scan",
                scanHistory: scanData,
                includeCharts: template?.includeCharts ?? false
            )

            exportProgress = 1.0
            task.status = .completed
            task.fileURL = fileURL

            isExporting = false
            return fileURL

        } catch {
            task.status = .failed
            task.errorMessage = error.localizedDescription
            isExporting = false
            throw error
        }
    }

    // MARK: - Private Methods

    private func fetchScanData(
        dateFrom: Date?,
        dateTo: Date?,
        source: String?,
        deviceType: String?
    ) async throws -> [ScanHistory] {
        // This would integrate with the backend service
        // For now, return mock data
        return [
            ScanHistory(
                id: UUID(),
                serial: "F2L3X8J9Q",
                confidence: 0.95,
                deviceType: "iPhone",
                source: "ios",
                timestamp: Date(),
                validationPassed: true,
                confidenceAcceptable: true
            )
        ]
    }

    private func transformData(_ data: [ScanHistory], format: ExportFormat) async throws -> ExportableData {
        switch format {
        case .excel:
            return try await transformForExcel(data)
        case .csv:
            return try await transformForCSV(data)
        case .json:
            return try await transformForJSON(data)
        case .googleSheets:
            return try await transformForGoogleSheets(data)
        case .appleNumbers:
            return try await transformForNumbers(data)
        }
    }

    private func transformBatchData(_ session: BatchSession, format: ExportFormat) async throws -> ExportableData {
        // Transform batch session data for export
        let batchData = BatchExportData(
            sessionName: session.name,
            createdAt: session.createdAt,
            completedAt: session.completedAt,
            totalItems: session.items.count,
            completedItems: session.completedItems,
            failedItems: session.failedItems,
            items: session.items.map { item in
                BatchItemExport(
                    deviceType: item.deviceType.rawValue,
                    serialNumber: item.serialNumber,
                    confidence: item.confidence,
                    timestamp: item.timestamp,
                    status: item.status.rawValue,
                    errorMessage: item.errorMessage
                )
            }
        )

        // Convert to appropriate format
        switch format {
        case .excel:
            return ExportableData.excel(data: batchData)
        case .csv:
            return ExportableData.csv(data: batchData)
        case .json:
            return ExportableData.json(data: batchData)
        case .googleSheets:
            return ExportableData.googleSheets(data: batchData)
        case .appleNumbers:
            return ExportableData.numbers(data: batchData)
        }
    }

    private func generateFile(_ data: ExportableData, format: ExportFormat, filename: String) async throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(filename)

        switch format {
        case .excel:
            try await generateExcelFile(data, url: fileURL)
        case .csv:
            try await generateCSVFile(data, url: fileURL)
        case .json:
            try await generateJSONFile(data, url: fileURL)
        case .googleSheets:
            // Google Sheets doesn't generate local files
            break
        case .appleNumbers:
            // Handled separately in exportToNumbers
            break
        }

        return fileURL
    }

    // MARK: - Format-specific Transformations

    private func transformForExcel(_ data: [ScanHistory]) async throws -> ExportableData {
        let headers = ["Device Type", "Serial Number", "Confidence", "Source", "Timestamp", "Validation", "Notes"]

        let rows = data.map { item in
            [
                item.deviceType,
                item.serial,
                String(format: "%.1f%%", item.confidence * 100),
                item.source,
                item.timestamp.formatted(),
                item.validationPassed ? "Valid" : "Invalid",
                "" // Notes field
            ]
        }

        return ExportableData.excel(headers: headers, rows: rows)
    }

    private func transformForCSV(_ data: [ScanHistory]) async throws -> ExportableData {
        let headers = ["Device Type", "Serial Number", "Confidence", "Source", "Timestamp", "Validation"]

        let rows = data.map { item in
            [
                item.deviceType,
                item.serial,
                String(format: "%.3f", item.confidence),
                item.source,
                item.timestamp.ISO8601Format(),
                item.validationPassed ? "true" : "false"
            ]
        }

        return ExportableData.csv(headers: headers, rows: rows)
    }

    private func transformForJSON(_ data: [ScanHistory]) async throws -> ExportableData {
        let jsonData = data.map { item in
            [
                "deviceType": item.deviceType,
                "serial": item.serial,
                "confidence": item.confidence,
                "source": item.source,
                "timestamp": item.timestamp.ISO8601Format(),
                "validationPassed": item.validationPassed,
                "confidenceAcceptable": item.confidenceAcceptable
            ] as [String: Any]
        }

        return ExportableData.json(data: jsonData)
    }

    private func transformForGoogleSheets(_ data: [ScanHistory]) async throws -> ExportableData {
        let headers = [["Device Type", "Serial Number", "Confidence", "Source", "Timestamp", "Validation"]]

        let rows = data.map { item in
            [
                item.deviceType,
                item.serial,
                String(format: "%.1f%%", item.confidence * 100),
                item.source,
                item.timestamp.formatted(),
                item.validationPassed ? "Valid" : "Invalid"
            ]
        }

        let allRows = headers + rows
        return ExportableData.googleSheets(values: allRows)
    }

    private func transformForNumbers(_ data: [ScanHistory], template: NumbersTemplate? = nil) async throws -> ExportableData {
        // Numbers-specific transformation
        let headers = ["Device Type", "Serial Number", "Confidence", "Source", "Timestamp"]

        let rows = data.map { item in
            [
                item.deviceType,
                item.serial,
                String(format: "%.1f%%", item.confidence * 100),
                item.source,
                item.timestamp.formatted()
            ]
        }

        return ExportableData.numbers(headers: headers, rows: rows, template: template)
    }

    // MARK: - File Generation

    private func generateExcelFile(_ data: ExportableData, url: URL) async throws {
        // Excel file generation logic
        // This would use a library like SwiftXLSX or similar
        let content = "Excel file content placeholder"
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func generateCSVFile(_ data: ExportableData, url: URL) async throws {
        guard case .csv(let headers, let rows) = data else { return }

        var content = headers.joined(separator: ",") + "\n"

        for row in rows {
            let escapedRow = row.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            content += escapedRow.joined(separator: ",") + "\n"
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func generateJSONFile(_ data: ExportableData, url: URL) async throws {
        guard case .json(let jsonData) = data else { return }

        let jsonDataObj = try JSONSerialization.data(withJSONObject: jsonData, options: .prettyPrinted)
        try jsonDataObj.write(to: url)
    }

    private func createOrUpdateGoogleSheet(data: ExportableData, spreadsheetId: String?) async throws -> String {
        // Google Sheets API integration
        // This would require Google Sheets API setup and authentication
        // For now, return a placeholder URL
        return "https://docs.google.com/spreadsheets/d/\(spreadsheetId ?? "new_spreadsheet_id")/edit"
    }

    private func generateNumbersFile(_ data: ExportableData, filename: String) async throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(filename)

        // Numbers file generation logic
        // This would require Numbers document format knowledge
        let content = "Numbers file content placeholder"
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        return fileURL
    }

    // MARK: - Utility Methods

    private func generateFilename(format: ExportFormat) -> String {
        let timestamp = Date().formatted(.iso8601)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "+", with: "_")

        switch format {
        case .excel:
            return "AppleSerialScan_\(timestamp).xlsx"
        case .csv:
            return "AppleSerialScan_\(timestamp).csv"
        case .json:
            return "AppleSerialScan_\(timestamp).json"
        case .googleSheets:
            return "GoogleSheets_\(timestamp)"
        case .appleNumbers:
            return "AppleSerialScan_\(timestamp).numbers"
        }
    }

    private func generateBatchFilename(session: BatchSession, format: ExportFormat) -> String {
        let cleanName = session.name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")

        let timestamp = Date().formatted(.iso8601)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "+", with: "_")

        switch format {
        case .excel:
            return "Batch_\(cleanName)_\(timestamp).xlsx"
        case .csv:
            return "Batch_\(cleanName)_\(timestamp).csv"
        case .json:
            return "Batch_\(cleanName)_\(timestamp).json"
        case .googleSheets:
            return "Batch_\(cleanName)_\(timestamp)"
        case .appleNumbers:
            return "Batch_\(cleanName)_\(timestamp).numbers"
        }
    }

    func getExportTasks() -> [ExportTask] {
        return exportTasks
    }

    func clearCompletedTasks() {
        exportTasks.removeAll { $0.status == .completed }
    }
}

// MARK: - Data Structures

struct ExportableData {
    enum DataType {
        case excel(headers: [String], rows: [[String]])
        case csv(headers: [String], rows: [[String]])
        case json(data: [[String: Any]])
        case googleSheets(values: [[String]])
        case numbers(headers: [String], rows: [[String]], template: NumbersTemplate?)
    }

    let type: DataType

    static func excel(headers: [String], rows: [[String]]) -> ExportableData {
        ExportableData(type: .excel(headers: headers, rows: rows))
    }

    static func excel(data: BatchExportData) -> ExportableData {
        let headers = ["Device Type", "Serial Number", "Confidence", "Status", "Timestamp"]
        let rows = data.items.map { item in
            [
                item.deviceType,
                item.serialNumber ?? "",
                item.confidence.map { String(format: "%.1f%%", $0 * 100) } ?? "",
                item.status,
                item.timestamp?.formatted() ?? ""
            ]
        }
        return ExportableData(type: .excel(headers: headers, rows: rows))
    }

    static func csv(headers: [String], rows: [[String]]) -> ExportableData {
        ExportableData(type: .csv(headers: headers, rows: rows))
    }

    static func csv(data: BatchExportData) -> ExportableData {
        let headers = ["Device Type", "Serial Number", "Confidence", "Status"]
        let rows = data.items.map { item in
            [
                item.deviceType,
                item.serialNumber ?? "",
                item.confidence.map { String(format: "%.3f", $0) } ?? "",
                item.status
            ]
        }
        return ExportableData(type: .csv(headers: headers, rows: rows))
    }

    static func json(data: [[String: Any]]) -> ExportableData {
        ExportableData(type: .json(data: data))
    }

    static func json(data: BatchExportData) -> ExportableData {
        let jsonData = data.items.map { item in
            [
                "deviceType": item.deviceType,
                "serialNumber": item.serialNumber ?? "",
                "confidence": item.confidence ?? 0.0,
                "status": item.status,
                "timestamp": item.timestamp?.ISO8601Format() ?? "",
                "errorMessage": item.errorMessage ?? ""
            ] as [String: Any]
        }
        return ExportableData(type: .json(data: jsonData))
    }

    static func googleSheets(values: [[String]]) -> ExportableData {
        ExportableData(type: .googleSheets(values: values))
    }

    static func googleSheets(data: BatchExportData) -> ExportableData {
        let headers = [["Device Type", "Serial Number", "Confidence", "Status", "Timestamp"]]
        let rows = data.items.map { item in
            [
                item.deviceType,
                item.serialNumber ?? "",
                item.confidence.map { String(format: "%.1f%%", $0 * 100) } ?? "",
                item.status,
                item.timestamp?.formatted() ?? ""
            ]
        }
        return ExportableData(type: .googleSheets(values: headers + rows))
    }

    static func numbers(headers: [String], rows: [[String]], template: NumbersTemplate?) -> ExportableData {
        ExportableData(type: .numbers(headers: headers, rows: rows, template: template))
    }

    static func numbers(data: BatchExportData) -> ExportableData {
        let headers = ["Device Type", "Serial Number", "Confidence", "Status"]
        let rows = data.items.map { item in
            [
                item.deviceType,
                item.serialNumber ?? "",
                item.confidence.map { String(format: "%.1f%%", $0 * 100) } ?? "",
                item.status
            ]
        }
        return ExportableData(type: .numbers(headers: headers, rows: rows, template: nil))
    }
}

struct BatchExportData {
    let sessionName: String
    let createdAt: Date
    let completedAt: Date?
    let totalItems: Int
    let completedItems: Int
    let failedItems: Int
    let items: [BatchItemExport]
}

struct BatchItemExport {
    let deviceType: String
    let serialNumber: String?
    let confidence: Float?
    let timestamp: Date?
    let status: String
    let errorMessage: String?
}

struct NumbersTemplate {
    let name: String
    let style: String
    let includeCharts: Bool
}

// MARK: - Google Sheets Integration (Implemented in GoogleSheetsService.swift)

// MARK: - Error Types
enum ExportError: Error {
    case invalidDataFormat
    case authenticationRequired
    case networkError
    case fileCreationFailed
    case serviceUnavailable
}

// MARK: - File Sharing
extension ExportManager {
    func shareFile(_ fileURL: URL, from viewController: UIViewController) {
        let activityViewController = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )

        // For iPad support
        if let popoverController = activityViewController.popoverPresentationController {
            popoverController.sourceView = viewController.view
            popoverController.sourceRect = CGRect(x: viewController.view.bounds.midX,
                                                y: viewController.view.bounds.midY,
                                                width: 0,
                                                height: 0)
            popoverController.permittedArrowDirections = []
        }

        viewController.present(activityViewController, animated: true)
    }

    func openInExternalApp(_ fileURL: URL, appURL: URL) {
        // Open file in external app (Numbers, Excel, etc.)
        UIApplication.shared.open(appURL)
    }
}
