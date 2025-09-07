import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SerialScannerViewModel()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Use the device-aware scanner view that automatically selects the best implementation
            DeviceTypeAwareScannerView(viewModel: viewModel)
                .tabItem {
                    Label("Scan", systemImage: "camera")
                }
                .tag(0)

            BatchProcessingView(scannerViewModel: viewModel)
                .tabItem {
                    Label("Batch", systemImage: "doc.on.doc")
                }
                .tag(1)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }
                .tag(2)

            ExportView()
                .tabItem {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .tag(3)

            AnalyticsDashboardView()
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar.fill")
                }
                .tag(4)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(5)
        }
    }
}
