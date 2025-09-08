import SwiftUI
import Foundation

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @State private var showingExportSheet = false
    @State private var showingFilterSheet = false
    @State private var searchText = ""
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack {
                // Search and filter bar
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Search serials...", text: $searchText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    Button(action: { showingFilterSheet = true }) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)
                
                // Stats summary
                if let stats = viewModel.systemStats {
                    StatsSummaryView(stats: stats)
                        .padding(.horizontal)
                }
                
                // History list
                if viewModel.isLoading {
                    Spacer()
                    ProgressView("Loading history...")
                    Spacer()
                } else if viewModel.scanHistory.isEmpty {
                    Spacer()
                    VStack {
                        Image(systemName: "doc.text")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text("No scan history")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("Scan some serial numbers to see them here")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(filteredHistory) { scan in
                            HistoryRowView(scan: scan)
                        }
                    }
                    .refreshable {
                        await viewModel.loadHistory()
                    }
                }
            }
            .navigationTitle("Scan History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingExportSheet = true }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(viewModel.scanHistory.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportView()
        }
        .sheet(isPresented: $showingFilterSheet) {
            FilterView(viewModel: viewModel)
        }
        .onAppear {
            Task {
                await viewModel.loadHistory()
                await viewModel.loadSystemStats()
            }
        }
    }
    
    private var filteredHistory: [ScanHistory] {
        if searchText.isEmpty {
            return viewModel.filteredHistory
        } else {
            return viewModel.filteredHistory.filter { scan in
                scan.serialNumber.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

// MARK: - Stats Summary View
struct StatsSummaryView: View {
    let stats: SystemStats
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                StatCard(title: "Total", value: "\(stats.totalScans)", color: .blue)
                StatCard(title: "Success", value: "\(stats.successfulScans)", color: .green)
                StatCard(title: "Failed", value: "\(stats.failedScans)", color: .red)
            }
            
            HStack {
                StatCard(title: "Success Rate", value: "\(Int(stats.successRate * 100))%", color: .orange)
                StatCard(title: "Avg Confidence", value: "\(Int(stats.averageConfidence * 100))%", color: .purple)
            }
        }
        .padding(.vertical, 8)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - History Row View
struct HistoryRowView: View {
    let scan: ScanHistory
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(scan.serialNumber)
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                HStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                }
            }
            
            HStack {
                Text(formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(deviceType.uppercased())
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
            }
            
            if let notes = scan.deviceModel, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        switch scan.status {
        case "Valid": return .green
        case "Pending": return .orange
        case "Invalid": return .red
        default: return .gray
        }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: scan.timestamp)
    }
    
    private var deviceType: String {
        return scan.deviceModel ?? "Unknown"
    }
}

// MARK: - History View Model
@MainActor
class HistoryViewModel: ObservableObject {
    @Published var scanHistory: [ScanHistory] = []
    @Published var systemStats: SystemStats?
    @Published var isLoading = false
    @Published var error: String?
    
    // Filter properties
    @Published var selectedSource: String = "all"
    @Published var selectedStatus: String = "all"
    @Published var dateRange: DateRange = .allTime
    
    enum DateRange: String, CaseIterable {
        case allTime = "All Time"
        case today = "Today"
        case week = "This Week"
        case month = "This Month"
        
        var days: Int? {
            switch self {
            case .allTime: return nil
            case .today: return 1
            case .week: return 7
            case .month: return 30
            }
        }
    }
    
    private let backendService = BackendService()
    
    var filteredHistory: [ScanHistory] {
        var filtered = scanHistory
        
        // Filter by status instead of source (since source doesn't exist in the model)
        if selectedSource != "all" {
            // We'll use deviceModel as a substitute for source, since that's what we have
            filtered = filtered.filter { $0.deviceModel?.lowercased() == selectedSource.lowercased() }
        }
        
        // Filter by status
        if selectedStatus != "all" {
            switch selectedStatus {
            case "success":
                filtered = filtered.filter { $0.status == "Valid" }
            case "borderline":
                filtered = filtered.filter { $0.status == "Pending" }
            case "failed":
                filtered = filtered.filter { $0.status == "Invalid" }
            default:
                break
            }
        }
        
        // Filter by date range
        if let days = dateRange.days {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            filtered = filtered.filter { $0.timestamp >= cutoffDate }
        }
        
        return filtered.sorted { $0.timestamp > $1.timestamp }
    }
    
    func loadHistory() async {
        isLoading = true
        error = nil

        do {
            // The backend returns a nested response with recent_scans array
            // We'll need to decode this properly
            guard let url = URL(string: "\(backendService.baseURL)/history?limit=100&offset=0") else {
                self.error = "Invalid URL"
                self.isLoading = false
                return
            }
            var request = URLRequest(url: url)
            if !backendService.apiKey.isEmpty {
                request.setValue("Bearer \(backendService.apiKey)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            // Parse the nested response
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let historyResponse = try decoder.decode(HistoryResponse.self, from: data)
            scanHistory = historyResponse.recentScans
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
    
    func loadSystemStats() async {
        do {
            systemStats = try await backendService.fetchSystemStats()
        } catch {
            // Don't show error for stats, just log it
            AppLogger.network.error("Failed to load system stats: \(error.localizedDescription)")
        }
    }
    
    func exportHistory(format: String) async -> Data? {
        do {
            return try await backendService.exportHistory(format: format)
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
    
    var availableSources: [String] {
        // Extract unique device models for filtering, using non-nil values only
        let sources = Set(scanHistory.compactMap { $0.deviceModel })
        return ["all"] + Array(sources).sorted()
    }
}

// MARK: - Filter View
struct FilterView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Source")) {
                    Picker("Source", selection: $viewModel.selectedSource) {
                        ForEach(viewModel.availableSources, id: \.self) { source in
                            Text(source == "all" ? "All Sources" : source.uppercased())
                                .tag(source)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                Section(header: Text("Status")) {
                    Picker("Status", selection: $viewModel.selectedStatus) {
                        Text("All").tag("all")
                        Text("Success").tag("success")
                        Text("Borderline").tag("borderline")
                        Text("Failed").tag("failed")
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                Section(header: Text("Date Range")) {
                    Picker("Date Range", selection: $viewModel.dateRange) {
                        ForEach(HistoryViewModel.DateRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}



struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView()
    }
}
