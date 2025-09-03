import SwiftUI

struct ExportView: View {
    @StateObject private var exportManager = ExportManager()
    @State private var selectedFormats: Set<ExportManager.ExportFormat> = [.excel]
    @State private var dateFrom: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var dateTo: Date = Date()
    @State private var selectedSource: String? = nil
    @State private var selectedDeviceType: String? = nil
    @State private var googleSheetsEnabled = false
    @State private var googleSpreadsheetId: String = ""
    @State private var showingDatePicker = false
    @State private var showingExportResult = false
    @State private var exportResultMessage = ""
    @State private var exportedFiles: [URL] = []

    let sources = ["ios", "mac", "server"]
    let deviceTypes = ["iPhone", "iPad", "MacBook", "iMac", "Apple Watch", "AirPods", "Other"]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {

                    // Export Progress
                    if exportManager.isExporting {
                        ExportProgressView(
                            progress: exportManager.exportProgress,
                            currentTask: exportManager.currentExportTask
                        )
                    }

                    // Export Formats
                    ExportFormatsSection(
                        selectedFormats: $selectedFormats,
                        googleSheetsEnabled: $googleSheetsEnabled,
                        googleSpreadsheetId: $googleSpreadsheetId
                    )

                    // Date Filtering
                    DateFilterSection(
                        dateFrom: $dateFrom,
                        dateTo: $dateTo,
                        showingDatePicker: $showingDatePicker
                    )

                    // Additional Filters
                    FilterSection(
                        selectedSource: $selectedSource,
                        selectedDeviceType: $selectedDeviceType,
                        sources: sources,
                        deviceTypes: deviceTypes
                    )

                    // Export Actions
                    ExportActionsSection(
                        exportManager: exportManager,
                        selectedFormats: selectedFormats,
                        dateFrom: dateFrom,
                        dateTo: dateTo,
                        selectedSource: selectedSource,
                        selectedDeviceType: selectedDeviceType,
                        googleSheetsEnabled: googleSheetsEnabled,
                        googleSpreadsheetId: googleSpreadsheetId,
                        showingExportResult: $showingExportResult,
                        exportResultMessage: $exportResultMessage,
                        exportedFiles: $exportedFiles
                    )

                    // Recent Exports
                    RecentExportsSection(exportManager: exportManager)

                    Spacer(minLength: 50)
                }
                .padding()
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Clear filters
                        resetFilters()
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                }
            }
            .sheet(isPresented: $showingDatePicker) {
                DatePickerSheet(dateFrom: $dateFrom, dateTo: $dateTo)
            }
            .alert("Export Result", isPresented: $showingExportResult) {
                Button("OK") {}
                if !exportedFiles.isEmpty {
                    Button("Share") {
                        shareExportedFiles()
                    }
                }
            } message: {
                Text(exportResultMessage)
            }
        }
    }

    private func resetFilters() {
        selectedFormats = [.excel]
        dateFrom = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        dateTo = Date()
        selectedSource = nil
        selectedDeviceType = nil
        googleSheetsEnabled = false
        googleSpreadsheetId = ""
    }

    private func shareExportedFiles() {
        // Implement file sharing
        print("Sharing files: \(exportedFiles)")
    }
}

// MARK: - Progress View
struct ExportProgressView: View {
    let progress: Double
    let currentTask: ExportManager.ExportTask?

    var body: some View {
        VStack(spacing: 12) {
            Text("Exporting...")
                .font(.headline)
                .foregroundColor(.blue)

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.blue)

            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)

            if let task = currentTask {
                Text("Processing: \(task.filename)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Export Formats Section
struct ExportFormatsSection: View {
    @Binding var selectedFormats: Set<ExportManager.ExportFormat>
    @Binding var googleSheetsEnabled: Bool
    @Binding var googleSpreadsheetId: String

    let availableFormats: [ExportManager.ExportFormat] = [.excel, .csv, .json, .appleNumbers]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Formats")
                .font(.headline)

            // Format Selection
            VStack(spacing: 12) {
                ForEach(availableFormats, id: \.self) { format in
                    ExportFormatRow(
                        format: format,
                        isSelected: selectedFormats.contains(format),
                        action: {
                            if selectedFormats.contains(format) {
                                selectedFormats.remove(format)
                            } else {
                                selectedFormats.insert(format)
                            }
                        }
                    )
                }
            }

            // Google Sheets Integration
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Export to Google Sheets", isOn: $googleSheetsEnabled)
                    .font(.subheadline)

                if googleSheetsEnabled {
                    TextField("Spreadsheet ID (optional)", text: $googleSpreadsheetId)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    Text("Leave blank to create new spreadsheet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4)
    }
}

// MARK: - Export Format Row
struct ExportFormatRow: View {
    let format: ExportManager.ExportFormat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: iconName)
                    .foregroundColor(isSelected ? .blue : .gray)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading) {
                    Text(formatName)
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private var formatName: String {
        switch format {
        case .excel: return "Microsoft Excel"
        case .csv: return "CSV File"
        case .json: return "JSON File"
        case .appleNumbers: return "Apple Numbers"
        case .googleSheets: return "Google Sheets"
        }
    }

    private var description: String {
        switch format {
        case .excel: return "Advanced formatting with charts"
        case .csv: return "Simple data for import"
        case .json: return "Structured data format"
        case .appleNumbers: return "Native macOS/iOS integration"
        case .googleSheets: return "Cloud-based spreadsheet"
        }
    }

    private var iconName: String {
        switch format {
        case .excel: return "tablecells"
        case .csv: return "doc.text"
        case .json: return "curlybraces"
        case .appleNumbers: return "number"
        case .googleSheets: return "cloud"
        }
    }
}

// MARK: - Date Filter Section
struct DateFilterSection: View {
    @Binding var dateFrom: Date
    @Binding var dateTo: Date
    @Binding var showingDatePicker: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date Range")
                .font(.headline)

            Button(action: { showingDatePicker = true }) {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.blue)

                    VStack(alignment: .leading) {
                        Text("From: \(dateFrom.formatted(date: .abbreviated, time: .omitted))")
                        Text("To: \(dateTo.formatted(date: .abbreviated, time: .omitted))")
                    }
                    .font(.subheadline)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4)
    }
}

// MARK: - Filter Section
struct FilterSection: View {
    @Binding var selectedSource: String?
    @Binding var selectedDeviceType: String?

    let sources: [String]
    let deviceTypes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Filters")
                .font(.headline)

            // Source Filter
            VStack(alignment: .leading, spacing: 8) {
                Text("Source")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Source", selection: $selectedSource) {
                    Text("All Sources").tag(String?.none)
                    ForEach(sources, id: \.self) { source in
                        Text(source.capitalized).tag(String?.some(source))
                    }
                }
                .pickerStyle(.segmented)
            }

            // Device Type Filter
            VStack(alignment: .leading, spacing: 8) {
                Text("Device Type")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Device Type", selection: $selectedDeviceType) {
                    Text("All Types").tag(String?.none)
                    ForEach(deviceTypes, id: \.self) { type in
                        Text(type).tag(String?.some(type))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4)
    }
}

// MARK: - Export Actions Section
struct ExportActionsSection: View {
    @ObservedObject var exportManager: ExportManager
    let selectedFormats: Set<ExportManager.ExportFormat>
    let dateFrom: Date
    let dateTo: Date
    let selectedSource: String?
    let selectedDeviceType: String?
    let googleSheetsEnabled: Bool
    let googleSpreadsheetId: String
    @Binding var showingExportResult: Bool
    @Binding var exportResultMessage: String
    @Binding var exportedFiles: [URL]

    var body: some View {
        VStack(spacing: 16) {
            // Export Button
            Button(action: performExport) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export Data")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(canExport ? Color.blue : Color.gray)
                .cornerRadius(12)
            }
            .disabled(!canExport || exportManager.isExporting)

            // Export Summary
            if !selectedFormats.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Export Summary:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    ForEach(Array(selectedFormats), id: \.self) { format in
                        Text("• \(formatDescription(format))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if googleSheetsEnabled {
                        Text("• Google Sheets integration")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4)
    }

    private var canExport: Bool {
        !selectedFormats.isEmpty || googleSheetsEnabled
    }

    private func formatDescription(_ format: ExportManager.ExportFormat) -> String {
        switch format {
        case .excel: return "Excel spreadsheet (.xlsx)"
        case .csv: return "CSV file (.csv)"
        case .json: return "JSON data (.json)"
        case .appleNumbers: return "Numbers spreadsheet (.numbers)"
        case .googleSheets: return "Google Sheets"
        }
    }

    private func performExport() {
        // Implementation for export action
        Task {
            do {
                var exportedFiles: [URL] = []
                var exportResults: [String] = []

                // Export to selected formats
                for format in selectedFormats {
                    switch format {
                    case .excel, .csv, .json:
                        let fileURL = try await exportManager.exportScanHistory(
                            format: format,
                            dateFrom: dateFrom,
                            dateTo: dateTo,
                            source: selectedSource,
                            deviceType: selectedDeviceType
                        )
                        exportedFiles.append(fileURL)
                        exportResults.append("\(formatDescription(format)): \(fileURL.lastPathComponent)")

                    case .appleNumbers:
                        let fileURL = try await exportManager.exportToNumbers(
                            scanData: [], // Would need to fetch actual data
                            template: NumbersTemplate.standard
                        )
                        exportedFiles.append(fileURL)
                        exportResults.append("Numbers: \(fileURL.lastPathComponent)")

                    case .googleSheets:
                        // Handled separately below
                        break
                    }
                }

                // Export to Google Sheets if enabled
                if googleSheetsEnabled {
                    let spreadsheetURL = try await exportManager.exportToGoogleSheets(
                        scanData: [], // Would need to fetch actual data
                        spreadsheetId: googleSpreadsheetId.isEmpty ? nil : googleSpreadsheetId
                    )
                    exportResults.append("Google Sheets: \(spreadsheetURL)")
                }

                // Show success message
                let resultMessage = """
                Export completed successfully!

                \(exportResults.joined(separator: "\n"))
                """

                showingExportResult = true
                exportResultMessage = resultMessage
                exportedFiles = exportedFiles

            } catch {
                // Show error message
                showingExportResult = true
                exportResultMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Recent Exports Section
struct RecentExportsSection: View {
    @ObservedObject var exportManager: ExportManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Exports")
                .font(.headline)

            if exportManager.getExportTasks().isEmpty {
                Text("No recent exports")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(exportManager.getExportTasks().prefix(5), id: \.id) { task in
                    ExportTaskRow(task: task)
                }

                if exportManager.getExportTasks().count > 5 {
                    Text("And \(exportManager.getExportTasks().count - 5) more...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4)
    }
}

// MARK: - Export Task Row
struct ExportTaskRow: View {
    let task: ExportManager.ExportTask

    var body: some View {
        HStack {
            Image(systemName: iconName)
                .foregroundColor(statusColor)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading) {
                Text(task.filename)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(task.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(task.status.rawValue)
                .font(.caption)
                .foregroundColor(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.1))
                .cornerRadius(8)
        }
        .padding(.vertical, 8)
    }

    private var iconName: String {
        switch task.format {
        case .excel: return "tablecells"
        case .csv: return "doc.text"
        case .json: return "curlybraces"
        case .appleNumbers: return "number"
        case .googleSheets: return "cloud"
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .completed: return .green
        case .inProgress: return .blue
        case .failed: return .red
        case .pending: return .gray
        case .cancelled: return .orange
        }
    }
}

// MARK: - Date Picker Sheet
struct DatePickerSheet: View {
    @Binding var dateFrom: Date
    @Binding var dateTo: Date
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                DatePicker("From Date", selection: $dateFrom, displayedComponents: .date)
                    .datePickerStyle(.graphical)

                DatePicker("To Date", selection: $dateTo, displayedComponents: .date)
                    .datePickerStyle(.graphical)

                Spacer()
            }
            .padding()
            .navigationTitle("Select Date Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Preview
struct ExportView_Previews: PreviewProvider {
    static var previews: some View {
        ExportView()
    }
}
