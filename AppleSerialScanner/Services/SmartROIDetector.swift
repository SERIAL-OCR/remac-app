import Foundation
import CoreImage
import Vision
import os.log

/// Smart Region of Interest detector that focuses OCR on likely serial number locations
@available(iOS 13.0, *)
class SmartROIDetector {
    
    // MARK: - Properties
    private let logger = Logger(subsystem: "com.appleserialscanner", category: "SmartROIDetector")
    
    // Device-specific ROI patterns
    private struct DeviceROIPattern {
        let deviceType: String
        let primaryROI: CGRect       // Most likely location
        let secondaryROIs: [CGRect]  // Alternative locations
        let minTextHeight: Float     // Expected text size
    }
    
    // Known Apple device patterns
    private let devicePatterns: [DeviceROIPattern] = [
        // iPhone patterns
        DeviceROIPattern(
            deviceType: "iPhone",
            primaryROI: CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.2),  // Bottom area
            secondaryROIs: [
                CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.15),  // Top area (settings)
                CGRect(x: 0.1, y: 0.4, width: 0.8, height: 0.2)    // Middle area
            ],
            minTextHeight: 0.015
        ),
        
        // iPad patterns  
        DeviceROIPattern(
            deviceType: "iPad",
            primaryROI: CGRect(x: 0.1, y: 0.75, width: 0.8, height: 0.15), // Bottom edge
            secondaryROIs: [
                CGRect(x: 0.2, y: 0.05, width: 0.6, height: 0.1),   // Top area (settings)
                CGRect(x: 0.6, y: 0.4, width: 0.35, height: 0.2)    // Right side (portrait mode)
            ],
            minTextHeight: 0.012
        ),
        
        // MacBook patterns
        DeviceROIPattern(
            deviceType: "MacBook",
            primaryROI: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.15),  // Bottom area
            secondaryROIs: [
                CGRect(x: 0.05, y: 0.4, width: 0.9, height: 0.2),   // Center strip
                CGRect(x: 0.2, y: 0.05, width: 0.6, height: 0.1)    // Top area
            ],
            minTextHeight: 0.01
        ),
        
        // Generic Apple device
        DeviceROIPattern(
            deviceType: "Generic",
            primaryROI: CGRect(x: 0.15, y: 0.4, width: 0.7, height: 0.2),  // Center area
            secondaryROIs: [
                CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.2),    // Bottom
                CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.2)     // Top
            ],
            minTextHeight: 0.015
        )
    ]
    
    init() {
        logger.debug("SmartROIDetector initialized")
    }
    
    // MARK: - Main ROI Detection
    
    /// Detects optimal ROI based on device type and surface classification
    func detectOptimalROI(
        deviceType: String? = nil,
        surfaceType: SurfaceType = .unknown,
        scanningMode: ScanningMode = .screen,
        imageSize: CGSize
    ) -> SmartROIResult {
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Select device pattern
        let pattern = selectDevicePattern(for: deviceType, scanningMode: scanningMode)
        
        // Adapt ROI based on surface type
        let adaptedROIs = adaptROIForSurface(pattern: pattern, surfaceType: surfaceType)
        
        // Generate scanning strategy
        let strategy = generateScanningStrategy(
            rois: adaptedROIs,
            imageSize: imageSize,
            surfaceType: surfaceType
        )
        
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        
        logger.info("🎯 Generated ROI strategy with \(strategy.regions.count) regions in \(String(format: "%.2f", processingTime * 1000))ms")
        
        return SmartROIResult(
            primaryROI: strategy.regions.first?.rect ?? pattern.primaryROI,
            allROIs: strategy.regions.map { $0.rect },
            scanningStrategy: strategy,
            confidence: calculateROIConfidence(for: pattern, surfaceType: surfaceType),
            processingTime: processingTime
        )
    }
    
    /// Analyzes image to find text-like regions for serial numbers
    func analyzeImageForTextRegions(
        image: CIImage,
        completion: @escaping (TextRegionAnalysis) -> Void
    ) {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Use Vision to detect text regions
        let request = VNDetectTextRectanglesRequest { request, error in
            let processingTime = CFAbsoluteTimeGetCurrent() - startTime
            
            guard error == nil,
                  let observations = request.results as? [VNTextObservation] else {
                self.logger.error("Text region detection failed: \(error?.localizedDescription ?? "Unknown error")")
                completion(TextRegionAnalysis(
                    textRegions: [],
                    serialLikeRegions: [],
                    confidence: 0.0,
                    processingTime: processingTime
                ))
                return
            }
            
            // Filter and score text regions
            let serialLikeRegions = self.filterSerialLikeRegions(observations)
            
            self.logger.debug("📝 Found \(observations.count) text regions, \(serialLikeRegions.count) serial-like")
            
            completion(TextRegionAnalysis(
                textRegions: observations.map { $0.boundingBox },
                serialLikeRegions: serialLikeRegions,
                confidence: self.calculateTextRegionConfidence(serialLikeRegions),
                processingTime: processingTime
            ))
        }
        
        // Configure request for serial number detection
        request.reportCharacterBoxes = false
        request.minimumTextHeight = 0.01
        request.maximumCandidates = 20
        
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                self.logger.error("Text region analysis failed: \(error.localizedDescription)")
                completion(TextRegionAnalysis(
                    textRegions: [],
                    serialLikeRegions: [],
                    confidence: 0.0,
                    processingTime: CFAbsoluteTimeGetCurrent() - startTime
                ))
            }
        }
    }
    
    // MARK: - Private Implementation
    
    private func selectDevicePattern(for deviceType: String?, scanningMode: ScanningMode) -> DeviceROIPattern {
        if let deviceType = deviceType {
            // Try to find specific device pattern
            if let pattern = devicePatterns.first(where: { deviceType.lowercased().contains($0.deviceType.lowercased()) }) {
                return pattern
            }
        }
        
        // Fallback to generic pattern
        return devicePatterns.last! // "Generic" pattern
    }
    
    private func adaptROIForSurface(pattern: DeviceROIPattern, surfaceType: SurfaceType) -> [CGRect] {
        var rois = [pattern.primaryROI] + pattern.secondaryROIs
        
        switch surfaceType {
        case .screen:
            // Screen serials often in settings or about sections
            rois = rois.map { expandROI($0, factor: 0.9) } // Slightly smaller for precision
            
        case .chassis, .metal:
            // Physical serial numbers, often smaller and in specific locations
            rois = rois.map { expandROI($0, factor: 1.2) } // Larger search area
            
        case .paper:
            // Labels can be anywhere, expand search
            rois = rois.map { expandROI($0, factor: 1.1) }
            
        case .unknown:
            // Keep original sizes
            break
            
        default:
            break
        }
        
        return rois
    }
    
    private func expandROI(_ roi: CGRect, factor: CGFloat) -> CGRect {
        let centerX = roi.midX
        let centerY = roi.midY
        let newWidth = min(roi.width * factor, 1.0)
        let newHeight = min(roi.height * factor, 1.0)
        
        return CGRect(
            x: max(0, centerX - newWidth / 2),
            y: max(0, centerY - newHeight / 2),
            width: min(newWidth, 1.0 - max(0, centerX - newWidth / 2)),
            height: min(newHeight, 1.0 - max(0, centerY - newHeight / 2))
        )
    }
    
    private func generateScanningStrategy(
        rois: [CGRect],
        imageSize: CGSize,
        surfaceType: SurfaceType
    ) -> ScanningStrategy {
        
        var regions: [ScanRegion] = []
        
        for (index, roi) in rois.enumerated() {
            let priority = index == 0 ? .high : .medium
            let expectedTextHeight = calculateExpectedTextHeight(for: surfaceType, roi: roi)
            
            regions.append(ScanRegion(
                rect: roi,
                priority: priority,
                expectedTextHeight: expectedTextHeight,
                confidence: calculateRegionConfidence(roi: roi, index: index)
            ))
        }
        
        return ScanningStrategy(
            regions: regions,
            scanOrder: .priorityBased,
            parallelProcessing: regions.count > 2
        )
    }
    
    private func calculateExpectedTextHeight(for surfaceType: SurfaceType, roi: CGRect) -> Float {
        let baseHeight: Float = 0.015
        
        switch surfaceType {
        case .screen:
            return baseHeight * 1.2  // Screen text is usually larger
        case .chassis, .metal:
            return baseHeight * 0.8  // Engraved text is often smaller
        case .paper:
            return baseHeight        // Standard printed text
        default:
            return baseHeight
        }
    }
    
    private func calculateRegionConfidence(roi: CGRect, index: Int) -> Float {
        // Primary region gets highest confidence
        let baseConfidence: Float = index == 0 ? 0.9 : 0.6
        
        // Adjust based on ROI characteristics
        let areaFactor = Float(roi.width * roi.height)
        let positionFactor = roi.midY > 0.5 ? 1.1 : 0.9  // Slight preference for bottom half
        
        return min(baseConfidence * positionFactor * (0.5 + areaFactor), 1.0)
    }
    
    private func calculateROIConfidence(for pattern: DeviceROIPattern, surfaceType: SurfaceType) -> Float {
        var confidence: Float = 0.7
        
        // Boost confidence for known good combinations
        if pattern.deviceType != "Generic" {
            confidence += 0.2
        }
        
        if surfaceType != .unknown {
            confidence += 0.1
        }
        
        return min(confidence, 1.0)
    }
    
    private func filterSerialLikeRegions(_ observations: [VNTextObservation]) -> [CGRect] {
        return observations.compactMap { observation in
            // Filter based on size and aspect ratio for serial-like text
            let aspectRatio = observation.boundingBox.width / observation.boundingBox.height
            let area = observation.boundingBox.width * observation.boundingBox.height
            
            // Serial numbers are typically horizontal (wider than tall) and medium-sized
            if aspectRatio > 2.0 && aspectRatio < 15.0 && area > 0.001 && area < 0.1 {
                return observation.boundingBox
            }
            
            return nil
        }
    }
    
    private func calculateTextRegionConfidence(_ regions: [CGRect]) -> Float {
        guard !regions.isEmpty else { return 0.0 }
        
        // Higher confidence with more serial-like regions found
        let regionCount = Float(regions.count)
        return min(0.3 + (regionCount * 0.2), 1.0)
    }
}

// MARK: - Supporting Types

struct SmartROIResult {
    let primaryROI: CGRect
    let allROIs: [CGRect]
    let scanningStrategy: ScanningStrategy
    let confidence: Float
    let processingTime: TimeInterval
}

struct TextRegionAnalysis {
    let textRegions: [CGRect]
    let serialLikeRegions: [CGRect]
    let confidence: Float
    let processingTime: TimeInterval
}

struct ScanRegion {
    let rect: CGRect
    let priority: ScanPriority
    let expectedTextHeight: Float
    let confidence: Float
}

enum ScanPriority {
    case high, medium, low
}

struct ScanningStrategy {
    let regions: [ScanRegion]
    let scanOrder: ScanOrder
    let parallelProcessing: Bool
}

enum ScanOrder {
    case sequential, priorityBased, confidence
}
