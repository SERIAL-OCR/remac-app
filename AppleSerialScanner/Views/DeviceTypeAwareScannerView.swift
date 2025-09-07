import SwiftUI
import UIKit

struct DeviceTypeAwareScannerView: View {
    @ObservedObject var viewModel = SerialScannerViewModel()
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Use our clean iPad-optimized scanner view on iPad
            CleanIPadScannerView(viewModel: viewModel)
                .onAppear {
                    // Apply iPad-specific optimizations if running on iPad
                    if let captureSession = viewModel.captureSession,
                       let textRecognitionRequest = viewModel.textRecognitionRequest {
                        IPadSerialScannerOptimizer.optimizeForIPad(
                            captureSession: captureSession,
                            textRecognitionRequest: textRecognitionRequest
                        )
                    }
                }
        } else {
            // Use the original scanner view on iPhone
            SerialScannerView(scannerViewModel: viewModel)
        }
    }
}
