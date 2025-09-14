import Foundation
import os.log

/// Unified diagnostics logging system for production-level error tracking
class DiagnosticsLogger {
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "Diagnostics")
    
    // Log storage
    private let queue = DispatchQueue(label: "com.appleserialscanner.diagnostics", qos: .utility)
    private var logEntries: [DiagnosticLogEntry] = []
    private let maxLogEntries = 10000
    
    // File management
    private let fileManager = FileManager.default
    private let archiveManager = LogArchiveManager()
    
    // Session tracking
    private var currentSessionId = UUID()
    private let sessionStartTime = Date()
    
    // MARK: - Public Methods
    
    /// Log a diagnostic event with optional context
    func logEvent(_ event: DiagnosticEvent, context: [String: Any]? = nil) {
        let entry = DiagnosticLogEntry(
            timestamp: Date(),
            sessionId: currentSessionId,
            event: event,
            context: context
        )
        
        queue.async {
            self.addLogEntry(entry)
            self.processLogEntry(entry)
        }
    }
    
    /// Get diagnostic logs for a time period
    func getLogs(since date: Date) -> [DiagnosticLogEntry] {
        queue.sync {
            return logEntries.filter { $0.timestamp >= date }
        }
    }
    
    /// Export diagnostic logs to file
    func exportLogs() -> URL? {
        queue.sync {
            do {
                let logs = try JSONEncoder().encode(logEntries)
                let url = try createLogFile()
                try logs.write(to: url)
                return url
            } catch {
                logger.error("Failed to export logs: \(error.localizedDescription)")
                return nil
            }
        }
    }
    
    /// Reset diagnostics system
    func reset() {
        queue.async {
            // Archive current logs before clearing
            self.archiveCurrentLogs()
            
            // Reset state
            self.logEntries.removeAll()
            self.currentSessionId = UUID()
        }
    }
    
    // MARK: - Private Methods
    
    private func addLogEntry(_ entry: DiagnosticLogEntry) {
        logEntries.append(entry)
        
        // Trim old entries if needed
        if logEntries.count > maxLogEntries {
            let excessEntries = logEntries.count - maxLogEntries
            logEntries.removeFirst(excessEntries)
        }
    }
    
    private func processLogEntry(_ entry: DiagnosticLogEntry) {
        // Log to system logger
        switch entry.event.severity {
        case .critical:
            logger.critical("\(entry.event.description) - \(entry.context ?? [:])")
        case .error:
            logger.error("\(entry.event.description) - \(entry.context ?? [:])")
        case .warning:
            logger.warning("\(entry.event.description) - \(entry.context ?? [:])")
        case .info:
            logger.info("\(entry.event.description) - \(entry.context ?? [:])")
        case .debug:
            logger.debug("\(entry.event.description) - \(entry.context ?? [:])")
        }
        
        // Handle critical events
        if entry.event.severity == .critical {
            handleCriticalEvent(entry)
        }
    }
    
    private func handleCriticalEvent(_ entry: DiagnosticLogEntry) {
        // Check for critical patterns
        analyzeCriticalPatterns()
        
        // Archive logs for critical events
        archiveCurrentLogs()
    }
    
    private func analyzeCriticalPatterns() {
        let recentEntries = logEntries.suffix(100)
        let criticalCount = recentEntries.filter { $0.event.severity == .critical }.count
        
        if criticalCount >= 3 {
            logger.critical("Multiple critical events detected - system may be unstable")
        }
    }
    
    private func createLogFile() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = formatter.string(from: Date())
        
        let filename = "diagnostics_\(timestamp).json"
        let docsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        
        return docsURL.appendingPathComponent(filename)
    }
    
    private func archiveCurrentLogs() {
        guard !logEntries.isEmpty else { return }
        
        do {
            if let url = try? createLogFile() {
                let logs = try JSONEncoder().encode(logEntries)
                try logs.write(to: url)
                
                // Archive the log file
                try archiveManager.archiveLog(at: url)
                
                logger.info("Successfully archived logs")
            }
        } catch {
            logger.error("Failed to archive logs: \(error.localizedDescription)")
        }
    }
}

// MARK: - Supporting Types

struct DiagnosticLogEntry: Codable {
    let id: UUID
    let timestamp: Date
    let sessionId: UUID
    let event: DiagnosticEvent
    let context: [String: Any]?

    init(timestamp: Date, sessionId: UUID, event: DiagnosticEvent, context: [String: Any]?) {
        self.id = UUID()
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.event = event
        self.context = context
    }
    
    enum CodingKeys: String, CodingKey {
        case id, timestamp, sessionId, event, context
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(event, forKey: .event)
        
        // Encode context as JSON string
        if let context = context {
            let contextData = try JSONSerialization.data(withJSONObject: context)
            let contextString = String(data: contextData, encoding: .utf8)
            try container.encode(contextString, forKey: .context)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        sessionId = try container.decode(UUID.self, forKey: .sessionId)
        event = try container.decode(DiagnosticEvent.self, forKey: .event)

        if let contextString = try? container.decode(String.self, forKey: .context) {
            if let data = contextString.data(using: .utf8) {
                if let obj = try? JSONSerialization.jsonObject(with: data, options: []), let dict = obj as? [String: Any] {
                    context = dict
                    return
                }
            }
        }

        context = nil
    }
}

struct DiagnosticEvent: Codable {
    let type: EventType
    let description: String
    let severity: EventSeverity
    let code: String
    
    enum EventType: String, Codable {
        case camera
        case recognition
        case validation
        case system
        case performance
    }
    
    enum EventSeverity: String, Codable {
        case critical
        case error
        case warning
        case info
        case debug
    }
}

/// Manages archiving of diagnostic logs
class LogArchiveManager {
    private let fileManager = FileManager.default
    private let maxArchiveAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    
    func archiveLog(at url: URL) throws {
        let archiveURL = try getArchiveDirectory()
            .appendingPathComponent(url.lastPathComponent)
        
        try fileManager.moveItem(at: url, to: archiveURL)
        cleanOldArchives()
    }
    
    private func getArchiveDirectory() throws -> URL {
        let docsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        
        let archiveURL = docsURL.appendingPathComponent("LogArchives")
        
        if !fileManager.fileExists(atPath: archiveURL.path) {
            try fileManager.createDirectory(
                at: archiveURL,
                withIntermediateDirectories: true
            )
        }
        
        return archiveURL
    }
    
    private func cleanOldArchives() {
        guard let archiveURL = try? getArchiveDirectory() else { return }
        
        do {
            let files = try fileManager.contentsOfDirectory(
                at: archiveURL,
                includingPropertiesForKeys: [.creationDateKey]
            )
            
            let oldFiles = files.filter {
                guard let creation = try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate else {
                    return false
                }
                return Date().timeIntervalSince(creation) > maxArchiveAge
            }
            
            try oldFiles.forEach { try fileManager.removeItem(at: $0) }
        } catch {
            print("Failed to clean archives: \(error.localizedDescription)")
        }
    }
}
