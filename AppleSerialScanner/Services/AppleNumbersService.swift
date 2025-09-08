import Foundation
import SwiftUI

// MARK: - Apple Numbers Service
@MainActor
class AppleNumbersService: ObservableObject {
    @Published var isProcessing = false
    @Published var lastExportURL: URL?

    // MARK: - Numbers Document Creation
    func createNumbersDocument(
        title: String,
        headers: [String],
        data: [[String]],
        template: NumbersTemplate? = nil
    ) async throws -> URL {
        isProcessing = true
        defer { isProcessing = false }

        let tempDirectory = FileManager.default.temporaryDirectory
        let timestamp = Date().formatted(.iso8601)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "+", with: "_")

        let filename = "\(title)_\(timestamp).numbers"
        let fileURL = tempDirectory.appendingPathComponent(filename)

        // Create Numbers-compatible data structure
        let numbersData = try createNumbersDataStructure(
            title: title,
            headers: headers,
            data: data,
            template: template
        )

        // Generate the Numbers file
        try await generateNumbersFile(data: numbersData, url: fileURL)

        lastExportURL = fileURL
        return fileURL
    }

    func exportScanHistory(
        title: String,
        scanHistory: [ScanHistory],
        includeCharts: Bool = true
    ) async throws -> URL {
        let headers = ["Device Model", "Serial Number", "Status", "Timestamp"]

        let data = scanHistory.map { scan in
            [
                scan.deviceModel ?? "Unknown",
                scan.serialNumber,
                scan.status,
                scan.timestamp.formatted()
            ]
        }

        let template = includeCharts ? NumbersTemplate.standard : NumbersTemplate.minimal
        return try await createNumbersDocument(
            title: title,
            headers: headers,
            data: data,
            template: template
        )
    }

    func exportBatchResults(
        session: BatchSession,
        includeStatistics: Bool = true
    ) async throws -> URL {
        let title = "Batch_\(session.name)"

        var allData: [[String]] = []

        // Session summary
        if includeStatistics {
            allData.append(["Session Summary"])
            allData.append(["Name", session.name])
            allData.append(["Created", session.createdAt.formatted()])
            allData.append(["Completed", session.completedAt?.formatted() ?? "In Progress"])
            allData.append(["Total Items", String(session.items.count)])
            allData.append(["Completed", String(session.completedItems)])
            allData.append(["Failed", String(session.failedItems)])
            allData.append([""]) // Empty row
        }

        // Item details
        allData.append(["Device Type", "Serial Number", "Confidence", "Status", "Timestamp", "Error"])

        for item in session.items {
            allData.append([
                item.deviceType.rawValue,
                item.serialNumber ?? "",
                item.confidence.map { String(format: "%.1f%%", $0 * 100) } ?? "",
                item.status.rawValue,
                item.timestamp?.formatted() ?? "",
                item.errorMessage ?? ""
            ])
        }

        return try await createNumbersDocument(
            title: title,
            headers: [], // Headers included in data
            data: allData,
            template: .standard
        )
    }

    // MARK: - Private Methods

    private func createNumbersDataStructure(
        title: String,
        headers: [String],
        data: [[String]],
        template: NumbersTemplate?
    ) throws -> NumbersDocumentData {
        var tables: [NumbersTable] = []

        // Main data table
        let mainTable = NumbersTable(
            name: "Data",
            headers: headers,
            rows: data,
            style: .standard // Simplified, as tableStyle is not on the new model
        )
        tables.append(mainTable)

        // Add summary tables based on template
        if let template = template, template.includeStatistics {
            tables.append(createSummaryTable(data: data))
            tables.append(createDeviceBreakdownTable(data: data))
        }

        return NumbersDocumentData(
            title: title,
            tables: tables,
            template: template
        )
    }

    private func createSummaryTable(data: [[String]]) -> NumbersTable {
        // Calculate summary statistics
        let totalRecords = data.count
        // Assuming the 'status' column is the third one now
        let validRecords = data.filter { $0.count > 2 && $0[2] == "Valid" }.count
        let invalidRecords = totalRecords - validRecords

        return NumbersTable(
            name: "Summary",
            headers: ["Metric", "Value"],
            rows: [
                ["Total Records", String(totalRecords)],
                ["Valid Records", String(validRecords)],
                ["Invalid Records", String(invalidRecords)],
                ["Success Rate", String(format: "%.1f%%", Double(validRecords) / Double(totalRecords) * 100)]
            ],
            style: .summary
        )
    }

    private func createDeviceBreakdownTable(data: [[String]]) -> NumbersTable {
        // Group by device type
        var deviceCounts: [String: Int] = [:]

        for row in data {
            if !row.isEmpty {
                let deviceType = row[0]
                deviceCounts[deviceType, default: 0] += 1
            }
        }

        let breakdownData = deviceCounts.map { [$0.key, String($0.value)] }

        return NumbersTable(
            name: "Device Breakdown",
            headers: ["Device Type", "Count"],
            rows: breakdownData,
            style: .breakdown
        )
    }

    private func createBatchStatisticsTable(data: [[String]]) -> NumbersTable {
        // Extract batch statistics from the data
        var stats: [String: String] = [:]

        for row in data {
            if row.count >= 2 && row[0] == "Total Items" {
                stats["Total Items"] = row[1]
            } else if row.count >= 2 && row[0] == "Completed" {
                stats["Completed"] = row[1]
            } else if row.count >= 2 && row[0] == "Failed" {
                stats["Failed"] = row[1]
            }
        }

        return NumbersTable(
            name: "Statistics",
            headers: ["Metric", "Value"],
            rows: stats.map { [$0.key, $0.value] },
            style: .statistics
        )
    }

    private func createAnalyticsTable(data: [[String]]) -> NumbersTable {
        // Create analytics data
        let confidenceValues = data.compactMap { row -> Double? in
            if row.count > 2, let confidenceStr = row[2].replacingOccurrences(of: "%", with: "").split(separator: ".").first,
               let confidence = Double(confidenceStr) {
                return confidence
            }
            return nil
        }

        let avgConfidence = confidenceValues.isEmpty ? 0 : confidenceValues.reduce(0, +) / Double(confidenceValues.count)

        return NumbersTable(
            name: "Analytics",
            headers: ["Metric", "Value"],
            rows: [
                ["Average Confidence", String(format: "%.1f%%", avgConfidence)],
                ["Total Records", String(data.count)],
                ["Data Points", String(confidenceValues.count)]
            ],
            style: .analytics
        )
    }

    private func generateNumbersFile(data: NumbersDocumentData, url: URL) async throws {
        // Create Numbers-compatible file structure
        // Note: This is a simplified implementation
        // In a real app, you'd need to use the Numbers file format specification
        // or use a library that can generate Numbers files

        let jsonData = try JSONEncoder().encode(data)
        try jsonData.write(to: url)
    }
}

// MARK: - Data Structures

struct NumbersDocumentData: Codable {
    let title: String
    let tables: [NumbersTable]
    let template: NumbersTemplate?
}

struct NumbersTable: Codable {
    let name: String
    let headers: [String]
    let rows: [[String]]
    let style: NumbersTableStyle
}

enum NumbersTableStyle: String, Codable {
    case standard
    case summary
    case breakdown
    case statistics
    case analytics
}

// MARK: - File Operations
#if os(iOS)
extension AppleNumbersService {
    func shareNumbersFile(_ fileURL: URL, from viewController: UIViewController) {
        let activityViewController = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )

        // For iPad support
        if let popoverController = activityViewController.popoverPresentationController {
            popoverController.sourceView = viewController.view
            popoverController.sourceRect = CGRect(x: viewController.view.bounds.midX,
                                                y: viewController.view.bounds.midY,
                                                width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }

        viewController.present(activityViewController, animated: true)
    }

    func openInNumbers(_ fileURL: URL) {
        // Open file in Numbers app
        guard let numbersURL = URL(string: "numbers://") else {
            AppLogger.ui.error("Could not create Numbers URL")
            return
        }
        if UIApplication.shared.canOpenURL(numbersURL) {
            UIApplication.shared.open(numbersURL)
        } else {
            // Fallback: show alert that Numbers is not installed
            AppLogger.ui.error("Numbers app is not available")
        }
    }
}
#elseif os(macOS)
import AppKit

extension AppleNumbersService {
    func shareNumbersFile(_ fileURL: URL, from window: NSWindow?) {
        let sharingServicePicker = NSSharingServicePicker(items: [fileURL])
        if let contentView = window?.contentView {
            sharingServicePicker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
        }
    }

    func openInNumbers(_ fileURL: URL) {
        NSWorkspace.shared.open(fileURL)
    }
}
#endif

extension AppleNumbersService {
    func cleanupTempFiles() {
        let tempDirectory = FileManager.default.temporaryDirectory

        do {
            let tempFiles = try FileManager.default.contentsOfDirectory(
                at: tempDirectory,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "numbers" }

            for file in tempFiles {
                // Only delete files older than 1 hour
                if let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                   let creationDate = attributes[.creationDate] as? Date,
                   Date().timeIntervalSince(creationDate) > 3600 {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        } catch {
            AppLogger.storage.error("Error cleaning up temp files: \(error.localizedDescription)")
        }
    }
}

// MARK: - Convenience Methods
extension AppleNumbersService {
    func exportWithTemplate(
        title: String,
        scanHistory: [ScanHistory],
        template: NumbersTemplate
    ) async throws -> URL {
        return try await exportScanHistory(
            title: title,
            scanHistory: scanHistory,
            includeCharts: template.includeCharts
        )
    }

    func quickExport(scanHistory: [ScanHistory]) async throws -> URL {
        return try await exportScanHistory(
            title: "AppleSerialScan_Export",
            scanHistory: scanHistory,
            includeCharts: false
        )
    }
}

#if os(iOS)
extension AppleNumbersService {
    func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return nil
        }
        
        var topController = rootViewController
        while let presentedViewController = topController.presentedViewController {
            topController = presentedViewController
        }
        return topController
    }
}
#endif
