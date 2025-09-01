import Foundation
import UIKit

// MARK: - Platform Detection
enum Platform {
    case iOS
    case macOS
}

struct PlatformDetector {
    static var current: Platform {
        #if os(iOS)
        return .iOS
        #elseif os(macOS)
        return .macOS
        #else
        return .iOS // Default fallback
        #endif
    }
    
    static var isiOS: Bool {
        return current == .iOS
    }
    
    static var isMacOS: Bool {
        return current == .macOS
    }
    
    static var deviceName: String {
        #if os(iOS)
        return UIDevice.current.model
        #else
        return "Mac"
        #endif
    }
    
    static var systemVersion: String {
        #if os(iOS)
        return UIDevice.current.systemVersion
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }
}

