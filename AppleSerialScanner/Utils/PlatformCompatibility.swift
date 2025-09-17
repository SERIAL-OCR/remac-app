// PlatformCompatibility.swift
// Provide lightweight typealiases so code that imports UIKit can compile on macOS by mapping common UIKit types to AppKit when available.

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit

// Map a few commonly-used UIKit types to AppKit equivalents for macOS builds.
// Add more aliases here only as needed when further compiler errors appear.
public typealias UIImage = NSImage
public typealias UIColor = NSColor
public typealias UIView = NSView
public typealias UIViewController = NSViewController
public typealias UIImageView = NSImageView

// Provide UIKit-like system color properties on macOS for cross-platform compatibility.
@available(macOS, introduced: 10.14)
extension NSColor {
    /// Light gray background similar to iOS systemGray6
    @objc public class var systemGray6: NSColor {
        return NSColor(calibratedWhite: 0.95, alpha: 1.0)
    }

    /// System background color fallback
    @objc public class var systemBackground: NSColor {
        // Use the window background color as a reasonable default on macOS
        return NSColor.windowBackgroundColor
    }
}

#endif
