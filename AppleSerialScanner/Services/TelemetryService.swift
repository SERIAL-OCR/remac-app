import Foundation
import os

/// Lightweight telemetry service for settings and critical events
final class TelemetryService {
    static let shared = TelemetryService()
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "Telemetry")
    private let diagnostics = DiagnosticsLogger()
    private let queue = DispatchQueue(label: "com.appleserialscanner.telemetry", qos: .utility)
    
    private init() {}
    
    /// Track a settings change
    func trackSettingChange(key: String, oldValue: String?, newValue: String?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.logger.info("Setting changed: \(key, privacy: .public) from \(oldValue ?? "<nil>") to \(newValue ?? "<nil>")")

            let event = DiagnosticEvent(
                type: .system,
                description: "Setting \(key) changed",
                severity: .info,
                code: "SETTING_CHANGE_\(key)"
            )

            var context: [String: Any] = ["key": key]
            context["old"] = oldValue ?? NSNull()
            context["new"] = newValue ?? NSNull()

            self.diagnostics.logEvent(event, context: context)
        }
    }

    /// Track a generic telemetry event
    func trackEvent(type: DiagnosticEvent.EventType, description: String, severity: DiagnosticEvent.EventSeverity, code: String, context: [String: Any]? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let event = DiagnosticEvent(type: type, description: description, severity: severity, code: code)
            self.diagnostics.logEvent(event, context: context)
        }
    }
}
