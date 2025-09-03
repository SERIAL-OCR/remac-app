import SwiftUI
import Foundation
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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
        return ExportableData(type: .excel(headers: headers, rows: rows))
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
        return ExportableData(type: .csv(headers: headers, rows: rows))
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
        return ExportableData(type: .json(data: data))
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
        return ExportableData(type: .googleSheets(values: values))
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
        return ExportableData(type: .numbers(headers: headers, rows: rows, template: template))
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


// MARK: - Google Sheets Integration (Implemented in GoogleSheetsService.swift)

// MARK: - Error Types
enum ExportError: Error {
    case invalidDataFormat
    case authenticationRequired
    case networkError
    case fileCreationFailed
    case serviceUnavailable
}

// MARK: - Export Manager
/// A class that manages exporting scan history data in various formats.
/// Supports Excel, CSV, JSON, Google Sheets, and Apple Numbers exports.
@MainActor
class ExportManager: ObservableObject {
    // MARK: - Published Properties
    
    /// Indicates whether an export operation is in progress
    @Published var isExporting = false
    
    /// The progress of the current export operation (0.0 to 1.0)
    @Published var exportProgress: Double = 0.0
    
    /// The current export task being processed
    @Published var currentExportTask: ExportTask?
    
    // MARK: - Private Properties
    
    private let backendService: BackendService
    private let googleSheetsService: GoogleSheetsService
    private let numbersService: AppleNumbersService
    private var exportTasks: [ExportTask] = []
    
    // MARK: - Initialization
    
    /// Default initializer that creates its own services.
    init() {
        self.backendService = BackendService()
        self.googleSheetsService = GoogleSheetsService()
        self.numbersService = AppleNumbersService()
    }
    
    /// Initializer for dependency injection, useful for testing.
    init(backendService: BackendService,
         googleSheetsService: GoogleSheetsService,
         numbersService: AppleNumbersService) {
        self.backendService = backendService
        self.googleSheetsService = googleSheetsService
        self.numbersService = numbersService
    }
    
    // MARK: - Export Formats
    
    /// Supported export file formats
    enum ExportFormat: String, CaseIterable {
        case excel = "Excel"
        case csv = "CSV"
        case json = "JSON"
        case googleSheets = "Google Sheets"
        case appleNumbers = "Apple Numbers"
        
        var fileExtension: String {
            switch self {
            case .excel: return "xlsx"
            case .csv: return "csv"
            case .json: return "json"
            case .googleSheets: return ""  // No file extension for cloud-based format
            case .appleNumbers: return "numbers"
            }
        }
        
        var icon: String {
            switch self {
            case .excel: return "doc.excel"
            case .csv: return "doc.text"
            case .json: return "doc.plaintext"
            case .googleSheets: return "doc.on.doc"
            case .appleNumbers: return "chart.bar.doc.horizontal"
            }
        }
    }

    // MARK: - Export Task
    
    /// Represents a single export operation with its status and metadata
    struct ExportTask: Identifiable, Equatable {
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
        
        static func == (lhs: ExportTask, rhs: ExportTask) -> Bool {
            lhs.id == rhs.id
        }
    }

    /// Possible states for an export operation
    enum ExportStatus: String {
        case pending = "Pending"
        case inProgress = "In Progress"
        case completed = "Completed"
        case failed = "Failed"
        case cancelled = "Cancelled"
    }

    /// Generates a filename for the export file
    /// - Parameter format: Export format
    /// - Returns: Formatted filename with timestamp
    private func generateFilename(format: ExportFormat) -> String {
        let timestamp = Date().formatted(.iso8601)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "+", with: "_")

        return "AppleSerialScan_\(timestamp).\(format.fileExtension)"
    }

    /// Generates a filename for batch export
    /// - Parameters:
    ///   - session: Batch session
    ///   - format: Export format
    /// - Returns: Formatted filename
    private func generateBatchFilename(session: BatchSession, format: ExportFormat) -> String {
        let cleanName = session.name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")

        let timestamp = Date().formatted(.iso8601)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "+", with: "_")

        return "Batch_\(cleanName)_\(timestamp).\(format.fileExtension)"
    }

    // MARK: - Export Methods

    /// Exports scan history to the specified format
    /// - Parameters:
    ///   - format: The export format (Excel, CSV, JSON, etc.)
    ///   - dateFrom: Optional start date filter
    ///   - dateTo: Optional end date filter
    ///   - source: Optional source filter
    ///   - deviceType: Optional device type filter
    /// - Returns: URL to the exported file
    func exportScanHistory(
        format: ExportFormat,
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        source: String? = nil,
        deviceType: String? = nil
    ) async throws -> URL {
        isExporting = true
        exportProgress = 0.0

        var task = ExportTask(
            format: format,
            filename: generateFilename(format: format)
        )

        currentExportTask = task
        exportTasks.append(task)

        do {
            // Update progress
            exportProgress = 0.1
            task.status = ExportStatus.inProgress
            // Update the copy in the array
            if let index = exportTasks.firstIndex(where: { $0.id == task.id }) {
                exportTasks[index].status = ExportStatus.inProgress
            }

            // Fetch data from backend
            let data = try await backendService.fetchHistory(dateFrom: dateFrom, dateTo: dateTo, source: source, deviceType: deviceType)

            exportProgress = 0.3

            // Transform data based on format
            let transformedData = try await self.transformData(data, format: format)

            exportProgress = 0.7

            // Generate file
            let fileURL = try await self.generateFile(transformedData, format: format, filename: task.filename)

            exportProgress = 1.0
            task.status = ExportStatus.completed
            task.fileURL = fileURL
            // Update the copy in the array
            if let index = exportTasks.firstIndex(where: { $0.id == task.id }) {
                exportTasks[index].status = ExportStatus.completed
                exportTasks[index].fileURL = fileURL
            }

            isExporting = false
            return fileURL

        } catch {
            task.status = ExportStatus.failed
            task.errorMessage = error.localizedDescription
            // Update the copy in the array
            if let index = exportTasks.firstIndex(where: { $0.id == task.id }) {
                exportTasks[index].status = ExportStatus.failed
                exportTasks[index].errorMessage = error.localizedDescription
            }
            isExporting = false
            throw error
        }
    }

    /// Exports batch processing results to one or more formats
    /// - Parameters:
    ///   - session: The batch session containing results to export
    ///   - formats: Array of export formats to use
    /// - Returns: Array of URLs to the exported files
    func exportBatchResults(_ session: BatchSession, formats: [ExportFormat] = [.excel, .csv]) async throws -> [URL] {
        isExporting = true
        exportProgress = 0.0

        var exportedFiles: [URL] = []
        let totalFormats = Double(formats.count)

        for (index, format) in formats.enumerated() {
            var task = ExportTask(
                format: format,
                filename: generateBatchFilename(session: session, format: format)
            )

            currentExportTask = task
            exportTasks.append(task)

            do {
                task.status = ExportStatus.inProgress
                // Update the copy in the array
                if let idx = exportTasks.firstIndex(where: { $0.id == task.id }) {
                    exportTasks[idx].status = ExportStatus.inProgress
                }

                // Transform batch data
                let transformedData = try await self.transformBatchData(session, format: format)

                exportProgress = (Double(index) + 0.7) / totalFormats

                // Generate file
                let fileURL = try await self.generateFile(transformedData, format: format, filename: task.filename)

                task.status = ExportStatus.completed
                task.fileURL = fileURL
                // Update the copy in the array
                if let idx = exportTasks.firstIndex(where: { $0.id == task.id }) {
                    exportTasks[idx].status = ExportStatus.completed
                    exportTasks[idx].fileURL = fileURL
                }
                
                exportedFiles.append(fileURL)

            } catch {
                task.status = ExportStatus.failed // Fixed from ExportError.failed
                task.errorMessage = error.localizedDescription
                // Update the copy in the array
                if let idx = exportTasks.firstIndex(where: { $0.id == task.id }) {
                    exportTasks[idx].status = ExportStatus.failed
                    exportTasks[idx].errorMessage = error.localizedDescription
                }
            }
        }

        exportProgress = 1.0
        isExporting = false
        return exportedFiles
    }

    // MARK: - Google Sheets Integration
    
    /// Exports scan data to Google Sheets
    /// - Parameters:
    ///   - scanData: Array of scan history items to export
    ///   - spreadsheetId: Optional existing spreadsheet ID to update
    /// - Returns: URL to the Google Sheets document
    func exportToGoogleSheets(
        scanData: [ScanHistory],
        spreadsheetId: String? = nil
    ) async throws -> String {
        isExporting = true
        exportProgress = 0.0

        var task = ExportTask(
            format: .googleSheets,
            filename: "GoogleSheets_\(Date().formatted())"
        )

        currentExportTask = task
        exportTasks.append(task)

        do {
            task.status = ExportStatus.inProgress
            // Update the copy in the array
            if let idx = exportTasks.firstIndex(where: { $0.id == task.id }) {
                exportTasks[idx].status = ExportStatus.inProgress
            }
            
            exportProgress = 0.2

            // Check authentication
            if !googleSheetsService.isAuthenticated {
                throw GoogleSheetsError.notAuthenticated
            }

            // Transform data for Google Sheets
            let sheetsData = try await self.transformForGoogleSheets(scanData)

            exportProgress = 0.5

            // Create or update Google Sheet
            let spreadsheetURL: String
            if let spreadsheetId = spreadsheetId {
                // Update existing spreadsheet
                if case .googleSheets(let values) = sheetsData.type {
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
                if case .googleSheets(let values) = sheetsData.type {
                    spreadsheetURL = try await googleSheetsService.createAndPopulateSpreadsheet(
                        title: title,
                        values: values
                    )
                } else {
                    throw ExportError.invalidDataFormat
                }
            }

            exportProgress = 1.0
            task.status = ExportStatus.completed
            // Update the copy in the array
            if let idx = exportTasks.firstIndex(where: { $0.id == task.id }) {
                exportTasks[idx].status = ExportStatus.completed
            }

            isExporting = false
            return spreadsheetURL

        } catch {
            task.status = ExportStatus.failed
            task.errorMessage = error.localizedDescription
            // Update the copy in the array
            if let idx = exportTasks.firstIndex(where: { $0.id == task.id }) {
                exportTasks[idx].status = ExportStatus.failed
                exportTasks[idx].errorMessage = error.localizedDescription
                }
            isExporting = false
            throw error
        }
    }

    // MARK: - Apple Numbers Integration
    
    /// Exports scan data to Apple Numbers format
    /// - Parameters:
    ///   - scanData: Array of scan history items to export
    ///   - template: Optional template to use for Numbers document
    /// - Returns: URL to the exported Numbers file
    func exportToNumbers(
        scanData: [ScanHistory],
        template: NumbersTemplate? = nil
    ) async throws -> URL {
        isExporting = true
        exportProgress = 0.0

        var task = ExportTask(
            format: .appleNumbers,
            filename: generateFilename(format: .appleNumbers)
        )

        currentExportTask = task
        exportTasks.append(task)

        do {
            task.status = ExportStatus.inProgress
            // Update the copy in the array
            if let idx = exportTasks.firstIndex(where: { $0.id == task.id }) {
                exportTasks[idx].status = ExportStatus.inProgress
            }
            
            exportProgress = 0.2

            // Export using Numbers service
            let fileURL = try await numbersService.exportScanHistory(
                title: "Apple Serial Scan",
                scanHistory: scanData,
                includeCharts: template?.includeCharts ?? false
            )

            exportProgress = 1.0
            task.status = ExportStatus.completed
            task.fileURL = fileURL
            // Update the copy in the array
            if let idx = exportTasks.firstIndex(where: { $0.id == task.id }) {
                exportTasks[idx].status = ExportStatus.completed
                exportTasks[idx].fileURL = fileURL
            }

            isExporting = false
            return fileURL

        } catch {
            task.status = ExportStatus.failed
            task.errorMessage = error.localizedDescription
            // Update the copy in the array
            if let idx = exportTasks.firstIndex(where: { $0.id == task.id }) {
                exportTasks[idx].status = ExportStatus.failed
                exportTasks[idx].errorMessage = error.localizedDescription
            }
            isExporting = false
            throw error
        }
    }
    
    // MARK: - Export Task Management
    
    /// Retrieves all export tasks
    /// - Returns: Array of export tasks
    func getExportTasks() -> [ExportTask] {
        return exportTasks
    }
    
    /// Removes completed tasks from the task list
    func clearCompletedTasks() {
        exportTasks.removeAll { $0.status == .completed }
    }
    
    /// Cancels an in-progress export task
    /// - Parameter id: ID of the task to cancel
    func cancelTask(id: UUID) {
        if let index = exportTasks.firstIndex(where: { $0.id == id && $0.status == ExportStatus.inProgress }) {
            exportTasks[index].status = .cancelled
            
            // If it's the current task, reset export state
            if currentExportTask?.id == id {
                isExporting = false
                currentExportTask = nil
            }
        }
    }
    
    /// Clears all export tasks
    func clearAllTasks() {
        exportTasks.removeAll()
    }
    
    // MARK: - Private Methods

    /// Fetches scan data from the backend service based on filter criteria
    /// - Parameters:
    ///   - dateFrom: Optional start date filter
    ///   - dateTo: Optional end date filter
    ///   - source: Optional source filter
    ///   - deviceType: Optional device type filter
    /// - Returns: Array of scan history items
    private func fetchScanData(
        dateFrom: Date?,
        dateTo: Date?,
        source: String?,
        deviceType: String?
    ) async throws -> [ScanHistory] {
        do {
            return try await backendService.fetchHistory(dateFrom: dateFrom, dateTo: dateTo, source: source, deviceType: deviceType)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw ExportError.networkError
        } catch {
            throw ExportError.serviceUnavailable
        }
    }

    /// Transforms scan data based on the requested export format
    /// - Parameters:
    ///   - data: Array of scan history items
    ///   - format: Export format (Excel, CSV, JSON, etc.)
    /// - Returns: Transformed data structure
    private func transformData(_ data: [ScanHistory], format: ExportFormat) async throws -> ExportableData {
        // Validate input data
        guard !data.isEmpty else {
            throw ExportError.invalidDataFormat
        }
        
        switch format {
        case .excel:
            return try await self.transformForExcel(data)
        case .csv:
            return try await self.transformForCSV(data)
        case .json:
            return try await self.transformForJSON(data)
        case .googleSheets:
            return try await self.transformForGoogleSheets(data)
        case .appleNumbers:
            return try await self.transformForNumbers(data)
        }
    }

    /// Transforms batch session data based on the requested export format
    /// - Parameters:
    ///   - session: Batch session with export data
    ///   - format: Export format (Excel, CSV, etc.)
    /// - Returns: Transformed data structure
    private func transformBatchData(_ session: BatchSession, format: ExportFormat) async throws -> ExportableData {
        // Validate session data
        guard !session.items.isEmpty else {
            throw ExportError.invalidDataFormat
        }
        
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

    /// Generates a file based on the transformed data and export format
    /// - Parameters:
    ///   - data: Transformed data
    ///   - format: Export format
    ///   - filename: Name for the output file
    /// - Returns: URL to the generated file
    private func generateFile(_ data: ExportableData, format: ExportFormat, filename: String) async throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(filename)
        
        // Check if we can write to the temp directory
        guard FileManager.default.isWritableFile(atPath: tempDirectory.path) else {
            throw ExportError.fileCreationFailed
        }

        switch format {
        case .excel:
            try await self.generateExcelFile(data: data, url: fileURL)
        case .csv:
            try await self.generateCSVFile(data: data, url: fileURL)
        case .json:
            try await self.generateJSONFile(data: data, url: fileURL)
        case .googleSheets, .appleNumbers:
            // These are handled by their specific export methods and don't generate local files here.
            break
        }

        // Verify the file was created (if it's a local file format)
        if format != .googleSheets && format != .appleNumbers {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw ExportError.fileCreationFailed
            }
        }

        return fileURL
    }

    /// Generates an Excel file from the provided data
    /// - Parameters:
    ///   - data: Transformed data
    ///   - url: Target file URL
    private func generateExcelFile(data: ExportableData, url: URL) async throws {
        guard case .excel(let headers, let rows) = data.type else {
            throw ExportError.invalidDataFormat
        }
        
        var content = headers.joined(separator: ",") + "\n"

        for row in rows {
            let escapedRow = row.map { cell in
                return "\"\(cell.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            content += escapedRow.joined(separator: ",") + "\n"
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Generates a CSV file from the provided data
    /// - Parameters:
    ///   - data: Transformed data
    ///   - url: Target file URL
    private func generateCSVFile(data: ExportableData, url: URL) async throws {
        guard case .csv(let headers, let rows) = data.type else {
            throw ExportError.invalidDataFormat
        }

        var content = headers.joined(separator: ",") + "\n"

        for row in rows {
            let escapedRow = row.map { cell in
                return "\"\(cell.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            content += escapedRow.joined(separator: ",") + "\n"
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Generates a JSON file from the provided data
    /// - Parameters:
    ///   - data: Transformed data
    ///   - url: Target file URL
    private func generateJSONFile(data: ExportableData, url: URL) async throws {
        guard case .json(let jsonData) = data.type else {
            throw ExportError.invalidDataFormat
        }

        let jsonDataObj = try JSONSerialization.data(withJSONObject: jsonData, options: .prettyPrinted)
        try jsonDataObj.write(to: url)
    }

    /// Creates or updates a Google Sheet with the provided data
    /// - Parameters:
    ///   - data: Transformed data
    ///   - spreadsheetId: Optional existing spreadsheet ID
    /// - Returns: URL to the Google Sheet
    private func createOrUpdateGoogleSheet(data: ExportableData, spreadsheetId: String?) async throws -> String {
        guard case .googleSheets(let values) = data.type else {
            throw ExportError.invalidDataFormat
        }

        if let spreadsheetId = spreadsheetId {
            // Update existing spreadsheet
            try await googleSheetsService.updateSpreadsheet(
                spreadsheetId: spreadsheetId,
                values: values
            )
            let spreadsheet = try await googleSheetsService.getSpreadsheet(spreadsheetId: spreadsheetId)
            return spreadsheet.spreadsheetUrl
        } else {
            // Create new spreadsheet
            let title = "Apple Serial Scan - \(Date().formatted(date: .abbreviated, time: .omitted))"
            return try await googleSheetsService.createAndPopulateSpreadsheet(
                title: title,
                values: values
            )
        }
    }

    /// Generates an Apple Numbers file with the provided data
    /// - Parameters:
    ///   - data: Transformed data
    ///   - filename: Name for the output file
    /// - Returns: URL to the generated file
    private func generateNumbersFile(data: ExportableData, filename: String) async throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(filename)

        guard case .numbers(let headers, let rows, _) = data.type else {
            throw ExportError.invalidDataFormat
        }

        var content = headers.joined(separator: ",") + "\n"

        for row in rows {
            let escapedRow = row.map { cell in
                return "\"\(cell.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            content += escapedRow.joined(separator: ",") + "\n"
        }

        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    // MARK: - Format-specific Transformations

    /// Transforms scan history data for Excel format
    /// - Parameter data: Array of scan history items
    /// - Returns: Transformed data structure
    private func transformForExcel(_ data: [ScanHistory]) async throws -> ExportableData {
        let headers = ["Device Model", "Serial Number", "Status", "Timestamp", "Notes"]

        let rows = data.map { item in
            [
                item.deviceModel ?? "Unknown",
                item.serialNumber,
                item.status,
                item.timestamp.formatted(),
                "" // Notes field
            ]
        }

        return ExportableData.excel(headers: headers, rows: rows)
    }

    /// Transforms scan history data for CSV format
    /// - Parameter data: Array of scan history items
    /// - Returns: Transformed data structure
    private func transformForCSV(_ data: [ScanHistory]) async throws -> ExportableData {
        let headers = ["Device Model", "Serial Number", "Status", "Timestamp"]

        let rows = data.map { item in
            [
                item.deviceModel ?? "Unknown",
                item.serialNumber,
                item.status,
                item.timestamp.ISO8601Format()
            ]
        }

        return ExportableData.csv(headers: headers, rows: rows)
    }

    /// Transforms scan history data for JSON format
    /// - Parameter data: Array of scan history items
    /// - Returns: Transformed data structure
    private func transformForJSON(_ data: [ScanHistory]) async throws -> ExportableData {
        let jsonData = data.map { item in
            [
                "id": item.id.uuidString,
                "deviceModel": item.deviceModel ?? "Unknown",
                "serialNumber": item.serialNumber,
                "status": item.status,
                "timestamp": item.timestamp.ISO8601Format()
            ] as [String: Any]
        }

        return ExportableData.json(data: jsonData)
    }

    /// Transforms scan history data for Google Sheets format
    /// - Parameter data: Array of scan history items
    /// - Returns: Transformed data structure
    private func transformForGoogleSheets(_ data: [ScanHistory]) async throws -> ExportableData {
        let headers = [["Device Model", "Serial Number", "Status", "Timestamp"]]

        let rows = data.map { item in
            [
                item.deviceModel ?? "Unknown",
                item.serialNumber,
                item.status,
                item.timestamp.formatted()
            ]
        }

        let allRows = headers + rows
        return ExportableData.googleSheets(values: allRows)
    }

    /// Transforms scan history data for Apple Numbers format
    /// - Parameter data: Array of scan history items
    /// - Returns: Transformed data structure
    private func transformForNumbers(_ data: [ScanHistory]) async throws -> ExportableData {
        // Numbers-specific transformation
        let headers = ["Device Model", "Serial Number", "Status", "Timestamp"]

        let rows = data.map { item in
            [
                item.deviceModel ?? "Unknown",
                item.serialNumber,
                item.status,
                item.timestamp.formatted()
            ]
        }

        return ExportableData.numbers(headers: headers, rows: rows, template: nil)
    }
}

// MARK: - File Sharing
#if os(iOS)
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
#elseif os(macOS)
extension ExportManager {
    func shareFile(_ fileURL: URL, from window: NSWindow? = nil) {
        // macOS sharing
        let sharingServicePicker = NSSharingServicePicker(items: [fileURL])
        if let window = window {
            sharingServicePicker.show(relativeTo: NSRect.zero, of: window.contentView!, preferredEdge: .minY)
        }
    }
    
    func openInExternalApp(_ fileURL: URL, appURL: URL) {
        // Open file in external app on macOS
        NSWorkspace.shared.open(fileURL)
    }
}
#endif
