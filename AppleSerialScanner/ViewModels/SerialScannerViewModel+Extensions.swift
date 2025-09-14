import Foundation
import os.log

// MARK: - Auto Submit Support

extension SerialScannerViewModel {
    private func submitSerial(_ serial: String) {
        submitSerial(serial)
    }
}

// MARK: - Logger Support

extension SerialScannerViewModel {
    private var logger: OSLog {
        return OSLog(subsystem: "com.appleserialscanner", category: "SerialScannerViewModel")
    }
}
