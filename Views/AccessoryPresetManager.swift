import SwiftUI
import Vision

// MARK: - Accessory Types
enum AccessoryType: String, CaseIterable, Identifiable {
    case iphone = "iPhone"
    case ipad = "iPad"
    case macbook = "MacBook"
    case imac = "iMac"
    case macMini = "Mac Mini"
    case macPro = "Mac Pro"
    case appleWatch = "Apple Watch"
    case airPods = "AirPods"
    case airPodsMax = "AirPods Max"
    case accessory = "Accessory"
    case auto = "Auto-Detect"

    var id: String { self.rawValue }

    var description: String {
        switch self {
        case .iphone: return "iPhone"
        case .ipad: return "iPad"
        case .macbook: return "MacBook"
        case .imac: return "iMac"
        case .macMini: return "Mac Mini"
        case .macPro: return "Mac Pro"
        case .appleWatch: return "Apple Watch"
        case .airPods: return "AirPods"
        case .airPodsMax: return "AirPods Max"
        case .accessory: return "Other Accessories"
        case .auto: return "Auto-Detect"
        }
    }

    var iconName: String {
        switch self {
        case .iphone: return "iphone"
        case .ipad: return "ipad"
        case .macbook: return "laptopcomputer"
        case .imac: return "desktopcomputer"
        case .macMini: return "macmini"
        case .macPro: return "macpro.gen3"
        case .appleWatch: return "applewatch"
        case .airPods: return "airpods"
        case .airPodsMax: return "airpodsmax"
        case .accessory: return "puzzlepiece"
        case .auto: return "eye"
        }
    }

    var serialFormat: String {
        switch self {
        case .iphone, .ipad:
            return "12-character alphanumeric"
        case .macbook, .imac, .macMini, .macPro:
            return "12-character alphanumeric"
        case .appleWatch:
            return "12-character alphanumeric"
        case .airPods, .airPodsMax:
            return "12-character alphanumeric"
        case .accessory:
            return "Variable length alphanumeric"
        case .auto:
            return "Auto-detect format"
        }
    }

    var typicalSerialLocation: String {
        switch self {
        case .iphone: return "Settings > General > About"
        case .ipad: return "Settings > General > About"
        case .macbook, .imac, .macMini, .macPro:
            return "Apple menu > About This Mac"
        case .appleWatch: return "Watch app > My Watch > General > About"
        case .airPods: return "Settings > Bluetooth > AirPods info"
        case .airPodsMax: return "Settings > Bluetooth > AirPods info"
        case .accessory: return "Product packaging or device settings"
        case .auto: return "Scan any Apple device"
        }
    }
}

// MARK: - OCR Settings for Accessories
struct AccessoryOCRSettings {
    let recognitionLevel: VNRequestTextRecognitionLevel
    let minimumTextHeight: Float
    let roiSize: CGSize
    let processingFrames: Int
    let confidenceThreshold: Float
    let allowlist: String?

    static func settingsFor(accessory: AccessoryType) -> AccessoryOCRSettings {
        switch accessory {
        case .iphone, .ipad:
            return AccessoryOCRSettings(
                recognitionLevel: .accurate,
                minimumTextHeight: 0.01,
                roiSize: CGSize(width: 0.6, height: 0.6),
                processingFrames: 8,
                confidenceThreshold: 0.75,
                allowlist: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            )

        case .macbook, .imac, .macMini, .macPro:
            return AccessoryOCRSettings(
                recognitionLevel: .accurate,
                minimumTextHeight: 0.008,
                roiSize: CGSize(width: 0.5, height: 0.5),
                processingFrames: 10,
                confidenceThreshold: 0.8,
                allowlist: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            )

        case .appleWatch:
            return AccessoryOCRSettings(
                recognitionLevel: .accurate,
                minimumTextHeight: 0.015,
                roiSize: CGSize(width: 0.7, height: 0.7),
                processingFrames: 6,
                confidenceThreshold: 0.7,
                allowlist: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            )

        case .airPods, .airPodsMax:
            return AccessoryOCRSettings(
                recognitionLevel: .accurate,
                minimumTextHeight: 0.012,
                roiSize: CGSize(width: 0.8, height: 0.8),
                processingFrames: 7,
                confidenceThreshold: 0.72,
                allowlist: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            )

        case .accessory:
            return AccessoryOCRSettings(
                recognitionLevel: .accurate,
                minimumTextHeight: 0.008,
                roiSize: CGSize(width: 0.9, height: 0.9),
                processingFrames: 12,
                confidenceThreshold: 0.65,
                allowlist: nil // Allow any characters for accessories
            )

        case .auto:
            return AccessoryOCRSettings(
                recognitionLevel: .accurate,
                minimumTextHeight: 0.01,
                roiSize: CGSize(width: 0.6, height: 0.6),
                processingFrames: 10,
                confidenceThreshold: 0.7,
                allowlist: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            )
        }
    }
}

// MARK: - Accessory Preset Manager
@MainActor
class AccessoryPresetManager: ObservableObject {
    @Published var selectedAccessoryType: AccessoryType = .auto {
        didSet {
            saveSelectedPreset()
            updateOCRSettings()
        }
    }

    @Published var currentOCRSettings: AccessoryOCRSettings

    private let userDefaultsKey = "selectedAccessoryType"

    init() {
        // Load saved preset or default to auto
        if let savedTypeRaw = UserDefaults.standard.string(forKey: userDefaultsKey),
           let savedType = AccessoryType(rawValue: savedTypeRaw) {
            selectedAccessoryType = savedType
        }

        currentOCRSettings = AccessoryOCRSettings.settingsFor(accessory: selectedAccessoryType)
    }

    private func saveSelectedPreset() {
        UserDefaults.standard.set(selectedAccessoryType.rawValue, forKey: userDefaultsKey)
    }

    private func updateOCRSettings() {
        currentOCRSettings = AccessoryOCRSettings.settingsFor(accessory: selectedAccessoryType)
    }

    func getGuidanceText() -> String {
        switch selectedAccessoryType {
        case .auto:
            return "Auto-detect mode: Position any Apple device serial number within the frame"
        case .accessory:
            return "Accessory mode: Position accessory serial within frame. Move closer for small text."
        default:
            return "\(selectedAccessoryType.description) mode: Position \(selectedAccessoryType.description.lowercased()) serial within the frame"
        }
    }

    func getSerialValidationPattern() -> String {
        switch selectedAccessoryType {
        case .iphone, .ipad, .macbook, .imac, .macMini, .macPro, .appleWatch, .airPods, .airPodsMax:
            return "^[A-Z0-9]{12}$"
        case .accessory:
            return "^[A-Z0-9]{8,20}$" // More flexible for accessories
        case .auto:
            return "^[A-Z0-9]{8,20}$" // Auto-detect with flexible pattern
        }
    }

    func shouldEnableAdvancedFeatures() -> Bool {
        // Enable advanced features for complex devices
        switch selectedAccessoryType {
        case .macbook, .imac, .macMini, .macPro:
            return true // Macs often need advanced surface detection
        case .accessory:
            return true // Accessories may need all features
        default:
            return false // Simpler devices work well with basic settings
        }
    }

    func getProcessingWindow() -> TimeInterval {
        switch selectedAccessoryType {
        case .accessory, .macbook, .imac, .macMini, .macPro:
            return 5.0 // More time for complex surfaces
        case .appleWatch, .airPods, .airPodsMax:
            return 3.0 // Faster for small devices
        default:
            return 4.0 // Standard time
        }
    }

    func getMaxFrames() -> Int {
        return currentOCRSettings.processingFrames
    }
}
