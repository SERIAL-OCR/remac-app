# Apple Serial Scanner - Libraries and Frameworks Documentation

## Overview
This document provides a comprehensive overview of all libraries, frameworks, and technologies used in the Apple Serial Scanner application. The application is built as a cross-platform solution supporting both iOS and macOS.

## Core Apple Frameworks

### User Interface Frameworks
- **SwiftUI** - Primary UI framework for modern declarative user interfaces
- **AppKit** - macOS native UI framework (used conditionally with `#if canImport(AppKit)`)
- **UIKit** - iOS native UI framework (used conditionally with `#if canImport(UIKit)`)

### Computer Vision & Machine Learning
- **Vision** - Apple's computer vision framework for text recognition and image analysis
- **VisionKit** - High-level vision framework for document scanning capabilities
- **CoreML** - Apple's machine learning framework for running trained models
- **CoreImage** - Image processing and filtering framework

### Camera & Media
- **AVFoundation** - Audio/video capture and processing framework
  - Used with `@preconcurrency` for async/await compatibility
- **Photos** - Photo library access framework

### System & Foundation
- **Foundation** - Core system services and data types
- **Combine** - Reactive programming framework for handling asynchronous events
- **os.log** - Apple's unified logging system
- **Network** - Low-level networking framework for connection monitoring

### Concurrency & Performance
- **Swift Concurrency** - Modern async/await patterns throughout the codebase
- **@MainActor** - Used extensively for UI thread safety
- **@preconcurrency** - Applied to legacy frameworks for compatibility

## Third-Party Libraries & Services

### Analytics & Data Export
- **Google Sheets API** - Integration for data export functionality
- **Apple Numbers** - Native spreadsheet integration for macOS

### Network Communication
- **URLSession** - For HTTP API communication with backend services
- **JSON** - Data serialization for API requests/responses

## Custom Framework Architecture

### Core Pipeline Components
1. **SerialScannerPipeline** - Master orchestrator for OCR processing
2. **ScreenDetector** - Device screen detection logic
3. **SurfacePolarityClassifier** - Surface type classification
4. **ImagePreprocessor** - Image enhancement and preparation
5. **VisionTextRecognizer** - Text recognition engine
6. **AmbiguityResolver** - Character disambiguation logic
7. **SerialValidator** - Apple serial number validation
8. **StabilityTracker** - Result stabilization across frames

### Machine Learning Models
- **CharacterDisambiguator** - ML model for resolving ambiguous characters (0/O, 1/I/L, 5/S)
- **SerialFormatClassifier** - ML model for validating Apple serial number formats
- **SerialRegionDetector** - ML model for detecting serial number regions
- **MLModelLoader** - Centralized lazy loading system for Core ML models

### Utility Components
- **BackgroundProcessingManager** - Background task management with QoS
- **CameraManager** - Camera configuration and management
- **CameraConfigurator** - Optimized camera settings for text scanning
- **PowerManagementService** - Battery and performance optimization
- **AppLogger** - Centralized logging system
- **SecureStore** - Secure credential storage

## Platform-Specific Features

### iOS-Specific
- iPad-optimized scanning interface
- Touch-based user interactions
- Device orientation handling
- iOS-specific camera APIs

### macOS-Specific
- Menu bar integration
- Keyboard shortcuts
- Window management
- macOS-specific file system access

## Cross-Platform Compatibility

The application uses conditional compilation to ensure compatibility across platforms:

```swift
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
```

### Device Detection
- Runtime platform detection using `PlatformDetector`
- Device-specific optimizations (iPhone vs iPad vs Mac)
- Adaptive UI layouts based on screen size and capabilities

## Performance Optimizations

### Background Processing
- **Multi-threaded Architecture** - Separate queues for OCR, analytics, and surface processing
- **Quality of Service (QoS)** - Prioritized task execution
- **Frame Throttling** - Intelligent frame skipping based on device capabilities
- **Memory Management** - Automatic model loading/unloading

### Adaptive Processing
- Device-specific frame skip rates (iPad: 2, iPhone: 1, Mac: 0)
- Processing throttling (50ms minimum between frames)
- Load-based processing adjustments

## Data Models & Serialization

### Core Data Models
- **SerialSubmission** - Serial number submission data
- **SerialResponse** - Backend response models
- **AnalyticsModels** - Comprehensive analytics data structures
- **ScanHistory** - Local scan history management
- **SystemHealthMetrics** - Performance monitoring data

### Export Formats
- **NumbersTemplate** - Apple Numbers integration
- **AnalyticsExportFormat** - Multiple export format support
- **JSON** - API communication format

## Security & Privacy

### Data Protection
- **SecureStore** - Encrypted credential storage
- **Local Processing** - OCR processing performed on-device
- **Privacy-First Design** - Minimal data transmission to backend

### Network Security
- **TLS/HTTPS** - Encrypted communication with backend services
- **API Key Management** - Secure API authentication
- **Network Monitoring** - Connection status tracking

## Testing Frameworks

### Test Infrastructure
- **XCTest** - Apple's testing framework
- **UI Testing** - Automated user interface testing
- **Unit Testing** - Core functionality testing

## Backend Integration

### API Communication
- **RESTful APIs** - HTTP-based communication
- **Retry Logic** - Exponential backoff for failed requests
- **Timeout Management** - 10-second request timeouts
- **Error Handling** - Comprehensive error response handling

### Supported Endpoints
- Serial number submission
- Scan history retrieval
- Analytics data upload
- Health status monitoring

## Development Tools & Build System

### Build Configuration
- **Xcode Project** - Native iOS/macOS development environment
- **Swift Package Manager** - Dependency management
- **Debug/Release Configurations** - Environment-specific builds

### Code Organization
- **MVVM Architecture** - Model-View-ViewModel pattern
- **Protocol-Oriented Design** - Extensible component architecture
- **Dependency Injection** - Loose coupling between components

## Future Technology Considerations

### Planned Enhancements
- **Core ML model updates** - Improved accuracy through model refinement
- **Additional export formats** - CSV, Excel integration
- **Cloud synchronization** - iCloud integration for scan history
- **Accessibility improvements** - VoiceOver and Dynamic Type support

## Version Compatibility

### Minimum Requirements
- **iOS 13.0+** - For modern SwiftUI and async/await support
- **macOS 11.0+** - For unified app architecture
- **Xcode 14.0+** - For latest Swift features

### Framework Versions
- **Swift 5.0+** - Modern Swift language features
- **SwiftUI 3.0+** - Latest UI framework capabilities
- **Core ML 4.0+** - Advanced machine learning features

---

*Last Updated: September 13, 2025*
*Document Version: 1.0*

This documentation reflects the current implementation of the Apple Serial Scanner application and will be updated as new technologies and frameworks are integrated.