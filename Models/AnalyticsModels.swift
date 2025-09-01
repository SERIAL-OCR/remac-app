import Foundation
import SwiftUI

// MARK: - Analytics Data Models

/// Comprehensive analytics data for OCR performance tracking
struct AnalyticsData: Codable {
    let sessionId: UUID
    let timestamp: Date
    let deviceInfo: DeviceInfo
    let scanSession: ScanSessionAnalytics
    let performanceMetrics: PerformanceMetrics
    let accuracyMetrics: AccuracyMetrics
    let systemHealth: SystemHealthMetrics

    init(sessionId: UUID = UUID(),
         deviceInfo: DeviceInfo = DeviceInfo(),
         scanSession: ScanSessionAnalytics,
         performanceMetrics: PerformanceMetrics,
         accuracyMetrics: AccuracyMetrics,
         systemHealth: SystemHealthMetrics) {
        self.sessionId = sessionId
        self.timestamp = Date()
        self.deviceInfo = deviceInfo
        self.scanSession = scanSession
        self.performanceMetrics = performanceMetrics
        self.accuracyMetrics = accuracyMetrics
        self.systemHealth = systemHealth
    }
}

/// Device and system information
struct DeviceInfo: Codable {
    let deviceType: String
    let osVersion: String
    let appVersion: String
    let accessoryPreset: String
    let cameraCapabilities: CameraCapabilities

    init() {
        #if os(iOS)
        self.deviceType = UIDevice.current.model
        self.osVersion = UIDevice.current.systemVersion
        #else
        self.deviceType = "Mac"
        self.osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #endif

        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        self.accessoryPreset = "Auto-Detect" // This would come from the preset manager
        self.cameraCapabilities = CameraCapabilities()
    }
}

/// Camera capabilities and settings
struct CameraCapabilities: Codable {
    let hasFlash: Bool
    let maxResolution: String
    let supportedFormats: [String]

    init() {
        #if os(iOS)
        // iOS camera detection
        self.hasFlash = true // Assume modern devices have flash
        self.maxResolution = "4K"
        self.supportedFormats = ["HEVC", "H.264", "JPEG"]
        #else
        // macOS camera detection
        self.hasFlash = false
        self.maxResolution = "1080p"
        self.supportedFormats = ["H.264", "JPEG"]
        #endif
    }
}

/// Analytics for a complete scan session
struct ScanSessionAnalytics: Codable {
    let sessionId: UUID
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    let totalFrames: Int
    let successfulFrames: Int
    let bestResult: ScanResult?
    let surfaceDetectionResults: [SurfaceDetectionEvent]
    let lightingConditionChanges: [LightingConditionEvent]
    let angleCorrectionEvents: [AngleCorrectionEvent]

    var successRate: Double {
        totalFrames > 0 ? Double(successfulFrames) / Double(totalFrames) : 0.0
    }

    var averageProcessingTime: TimeInterval {
        duration > 0 ? duration / Double(totalFrames) : 0.0
    }
}

/// Individual scan result data
struct ScanResult: Codable {
    let serialNumber: String
    let confidence: Float
    let processingTime: TimeInterval
    let surfaceType: String
    let lightingCondition: String
    let angleCorrection: Bool
    let frameCount: Int
    let timestamp: Date
    let validationStatus: String
}

/// Surface detection events during scanning
struct SurfaceDetectionEvent: Codable {
    let timestamp: Date
    let surfaceType: String
    let confidence: Float
    let changedFrom: String?
}

/// Lighting condition changes during scanning
struct LightingConditionEvent: Codable {
    let timestamp: Date
    let lightingCondition: String
    let confidence: Float
    let changedFrom: String?
}

/// Angle correction events during scanning
struct AngleCorrectionEvent: Codable {
    let timestamp: Date
    let angleDegrees: Double
    let correctionApplied: Bool
    let confidence: Float
}

/// Performance metrics for the session
struct PerformanceMetrics: Codable {
    let averageProcessingTime: TimeInterval
    let minProcessingTime: TimeInterval
    let maxProcessingTime: TimeInterval
    let framesPerSecond: Double
    let memoryUsage: MemoryUsage
    let cpuUsage: CPUUsage
    let gpuUsage: GPUUsage?

    var processingTimeVariance: TimeInterval {
        if maxProcessingTime > minProcessingTime {
            return maxProcessingTime - minProcessingTime
        }
        return 0.0
    }
}

/// Memory usage statistics
struct MemoryUsage: Codable {
    let peakUsage: UInt64
    let averageUsage: UInt64
    let currentUsage: UInt64
    let availableMemory: UInt64
}

/// CPU usage statistics
struct CPUUsage: Codable {
    let averageUsage: Double
    let peakUsage: Double
    let coreCount: Int
}

/// GPU usage statistics (Apple Silicon)
struct GPUUsage: Codable {
    let averageUsage: Double
    let peakUsage: Double
    let memoryUsage: UInt64
}

/// Accuracy metrics for the session
struct AccuracyMetrics: Codable {
    let initialConfidence: Float
    let finalConfidence: Float
    let confidenceImprovement: Float
    let validationPassed: Bool
    let errorType: String?
    let retryCount: Int
    let surfaceAdaptationApplied: Bool
    let lightingAdaptationApplied: Bool
    let angleCorrectionApplied: Bool

    var confidenceGain: Float {
        finalConfidence - initialConfidence
    }
}

/// System health metrics during scanning
struct SystemHealthMetrics: Codable {
    let batteryLevel: Float?
    let thermalState: String
    let networkConnectivity: String
    let storageAvailable: UInt64
    let appCrashes: Int
    let systemWarnings: Int

    init() {
        #if os(iOS)
        self.batteryLevel = UIDevice.current.batteryLevel
        #else
        self.batteryLevel = nil
        #endif

        self.thermalState = "nominal" // Would need to implement thermal state detection
        self.networkConnectivity = "wifi" // Would need network detection
        self.storageAvailable = 1000000000 // 1GB placeholder - would need actual detection
        self.appCrashes = 0
        self.systemWarnings = 0
    }
}

// MARK: - Analytics Aggregation Models

/// Daily analytics summary
struct DailyAnalyticsSummary: Identifiable, Codable {
    let id: UUID
    let date: Date
    let totalSessions: Int
    let successfulSessions: Int
    let averageSessionDuration: TimeInterval
    let averageAccuracy: Double
    let averageProcessingTime: TimeInterval
    let topSurfaceTypes: [String: Int]
    let topFailureReasons: [String: Int]
    let systemHealthScore: Double

    var successRate: Double {
        totalSessions > 0 ? Double(successfulSessions) / Double(totalSessions) : 0.0
    }
}

/// Weekly analytics trends
struct WeeklyAnalyticsTrend: Identifiable, Codable {
    let id: UUID
    let weekStart: Date
    let accuracyTrend: [Date: Double]
    let performanceTrend: [Date: TimeInterval]
    let usageTrend: [Date: Int]
    let surfaceTypeDistribution: [String: Double]
    let improvementAreas: [String]
}

/// Analytics dashboard data
struct AnalyticsDashboardData {
    let todaySummary: DailyAnalyticsSummary
    let weeklyTrend: WeeklyAnalyticsTrend
    let recentSessions: [AnalyticsData]
    let systemHealth: SystemHealthMetrics
    let performanceInsights: [PerformanceInsight]
}

/// Performance insights and recommendations
struct PerformanceInsight: Identifiable {
    let id = UUID()
    let type: InsightType
    let title: String
    let description: String
    let impact: InsightImpact
    let recommendation: String
    let confidence: Double
}

enum InsightType {
    case accuracy
    case performance
    case usability
    case reliability
}

enum InsightImpact {
    case low
    case medium
    case high
    case critical
}

// MARK: - Analytics Service Models

/// Analytics collection configuration
struct AnalyticsConfiguration {
    let enableDataCollection: Bool
    let retentionPeriod: TimeInterval // in days
    let enableRemoteSync: Bool
    let anonymizeData: Bool
    let enablePerformanceTracking: Bool
    let enableErrorTracking: Bool

    static let `default` = AnalyticsConfiguration(
        enableDataCollection: true,
        retentionPeriod: 90, // 90 days
        enableRemoteSync: false,
        anonymizeData: true,
        enablePerformanceTracking: true,
        enableErrorTracking: true
    )
}

/// Analytics export formats
enum AnalyticsExportFormat {
    case json
    case csv
    case pdf
    case excel
}

/// Analytics query filters
struct AnalyticsFilters {
    let dateRange: ClosedRange<Date>?
    let deviceTypes: [String]?
    let surfaceTypes: [String]?
    let successStatus: Bool?
    let minConfidence: Float?
    let maxProcessingTime: TimeInterval?
}
