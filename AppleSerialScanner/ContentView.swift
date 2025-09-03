//
//  ContentView.swift
//  AppleSerialScanner
//
//  Created on Phase 2.2 - Multi-platform iOS/macOS Scanner
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SerialScannerViewModel()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            SerialScannerView(scannerViewModel: viewModel)
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
        .onAppear {
            // Configure appearance for both iOS and macOS
            #if os(iOS)
            UITabBar.appearance().backgroundColor = UIColor.systemBackground
            #endif
        }
    }
}

#Preview {
    ContentView()
}
