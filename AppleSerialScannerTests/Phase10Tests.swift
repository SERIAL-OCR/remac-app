import XCTest
@testable import AppleSerialScanner

final class Phase10Tests: XCTestCase {
    func testEnhancedSerialValidatorValidSerial() {
        let validator = SerialValidator()
        let result = validator.validateSerial("ABCDEFG12345")
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.cleanedSerial.count, 12)
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
