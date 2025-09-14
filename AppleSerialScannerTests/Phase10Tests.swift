import XCTest
@testable import AppleSerialScanner

final class Phase10Tests: XCTestCase {
    func testEnhancedSerialValidatorValidSerial() {
        let validator = EnhancedSerialValidator()
        let result = validator.validateSerial("ABCDEFG12345", confidence: 0.9)

        switch result {
        case .valid(let cleaned):
            XCTAssertEqual(cleaned.count, 12)
        default:
            XCTFail("Expected valid result for a 12-char alphanumeric serial")
        }
    }

    func testTelemetryTrackSettingChangeDoesNotCrash() {
        // This test ensures that calling telemetry tracking is safe on background queue
        let expectation = self.expectation(description: "Telemetry call completes")

        DispatchQueue.global().async {
            TelemetryService.shared.trackSettingChange(key: "scannerLanguages", oldValue: "en", newValue: "en-US")
            TelemetryService.shared.trackSettingChange(key: "stabilityThreshold", oldValue: "0.80", newValue: "0.85")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
    }
}
