import CoreML
import CoreVideo
import CoreImage
import Vision
import Accelerate
import os.log

/// Utility functions for Core ML operations including pixel buffer conversions and geometric transformations
@available(iOS 13.0, *)
public final class MLUtils {
    
    private static let logger = Logger(subsystem: "AppleSerialScanner", category: "MLUtils")
    
    // MARK: - Pixel Buffer Conversions
    
    /// Convert CGImage to CVPixelBuffer
    public static func pixelBuffer(from cgImage: CGImage, targetSize: CGSize? = nil) -> CVPixelBuffer? {
        let size = targetSize ?? CGSize(width: cgImage.width, height: cgImage.height)
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            logger.error("Failed to create pixel buffer from CGImage")
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            logger.error("Failed to create CGContext for pixel buffer")
            return nil
        }
        
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return buffer
    }
    
    /// Convert CIImage to CVPixelBuffer
    public static func pixelBuffer(from ciImage: CIImage, context: CIContext? = nil) -> CVPixelBuffer? {
        let ciContext = context ?? CIContext()
        let size = ciImage.extent.size
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            logger.error("Failed to create pixel buffer from CIImage")
            return nil
        }
        
        ciContext.render(ciImage, to: buffer)
        return buffer
    }
    
    /// Convert CVPixelBuffer to CGImage
    public static func cgImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
    
    // MARK: - Cropping and Scaling
    
    /// Crop CVPixelBuffer to specified region
    public static func cropPixelBuffer(_ pixelBuffer: CVPixelBuffer, to rect: CGRect) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let croppedImage = ciImage.cropped(to: rect)
        return MLUtils.pixelBuffer(from: croppedImage)
    }
    
    /// Scale CVPixelBuffer to target size with letterboxing
    public static func scalePixelBufferWithLetterboxing(
        _ pixelBuffer: CVPixelBuffer,
        to targetSize: CGSize,
        fillColor: CGColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    ) -> CVPixelBuffer? {
        
        let sourceSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        
        // Calculate scale factor maintaining aspect ratio
        let scaleX = targetSize.width / sourceSize.width
        let scaleY = targetSize.height / sourceSize.height
        let scale = min(scaleX, scaleY)
        
        let scaledSize = CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
        
        // Calculate centering offset
        let offsetX = (targetSize.width - scaledSize.width) / 2
        let offsetY = (targetSize.height - scaledSize.height) / 2
        
        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(targetSize.width),
            Int(targetSize.height),
            kCVPixelFormatType_32BGRA,
            nil,
            &outputBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = outputBuffer else {
            logger.error("Failed to create output buffer for letterboxing")
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            logger.error("Failed to create CGContext for letterboxing")
            return nil
        }
        
        // Fill with background color
        context.setFillColor(fillColor)
        context.fill(CGRect(origin: .zero, size: targetSize))
        
        // Draw scaled image
        if let sourceImage = cgImage(from: pixelBuffer) {
            let drawRect = CGRect(
                x: offsetX,
                y: offsetY,
                width: scaledSize.width,
                height: scaledSize.height
            )
            context.draw(sourceImage, in: drawRect)
        }
        
        return buffer
    }
    
    // MARK: - Coordinate Conversions
    
    /// Convert normalized coordinates to pixel coordinates
    public static func denormalizeRect(_ normalizedRect: CGRect, imageSize: CGSize) -> CGRect {
        return CGRect(
            x: normalizedRect.origin.x * imageSize.width,
            y: normalizedRect.origin.y * imageSize.height,
            width: normalizedRect.width * imageSize.width,
            height: normalizedRect.height * imageSize.height
        )
    }
    
    /// Convert pixel coordinates to normalized coordinates
    public static func normalizeRect(_ pixelRect: CGRect, imageSize: CGSize) -> CGRect {
        return CGRect(
            x: pixelRect.origin.x / imageSize.width,
            y: pixelRect.origin.y / imageSize.height,
            width: pixelRect.width / imageSize.width,
            height: pixelRect.height / imageSize.height
        )
    }
    
    /// Convert Vision coordinate system to UIKit coordinate system
    public static func convertVisionToUIKit(_ rect: CGRect, imageHeight: CGFloat) -> CGRect {
        return CGRect(
            x: rect.origin.x,
            y: imageHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
    
    /// Convert UIKit coordinate system to Vision coordinate system
    public static func convertUIKitToVision(_ rect: CGRect, imageHeight: CGFloat) -> CGRect {
        return CGRect(
            x: rect.origin.x,
            y: imageHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
    
    // MARK: - MLMultiArray Utilities
    
    /// Create MLMultiArray from Float array
    public static func createMLMultiArray(from values: [Float], shape: [NSNumber]) -> MLMultiArray? {
        do {
            let multiArray = try MLMultiArray(shape: shape, dataType: .float32)
            let pointer = UnsafeMutablePointer<Float>(OpaquePointer(multiArray.dataPointer))
            
            for (index, value) in values.enumerated() {
                pointer[index] = value
            }
            
            return multiArray
        } catch {
            logger.error("Failed to create MLMultiArray: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Extract Float array from MLMultiArray
    public static func extractFloatArray(from multiArray: MLMultiArray) -> [Float] {
        let pointer = UnsafePointer<Float>(OpaquePointer(multiArray.dataPointer))
        let count = multiArray.count
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }
    
    /// Create text features from string for classification
    public static func createTextFeatures(from text: String, maxLength: Int = 128) -> MLMultiArray? {
        // Simple character-based encoding (in production, use proper embeddings)
        let characters = Array(text.lowercased().prefix(maxLength))
        var features = [Float](repeating: 0.0, count: maxLength)
        
        for (index, char) in characters.enumerated() {
            // Simple ASCII-based encoding
            if char.isLetter {
                features[index] = Float(char.asciiValue ?? 0) / 255.0
            } else if char.isNumber {
                features[index] = Float(char.asciiValue ?? 0) / 255.0 + 0.1
            }
        }
        
        return createMLMultiArray(from: features, shape: [1, NSNumber(value: maxLength)])
    }
    
    /// Create geometry features from text bounding box
    public static func createGeometryFeatures(
        from boundingBox: CGRect,
        imageSize: CGSize,
        confidence: Float = 1.0
    ) -> MLMultiArray? {
        
        let normalizedBox = normalizeRect(boundingBox, imageSize: imageSize)
        let aspectRatio = boundingBox.width / boundingBox.height
        let area = normalizedBox.width * normalizedBox.height
        
        let features: [Float] = [
            Float(normalizedBox.origin.x),      // x position
            Float(normalizedBox.origin.y),      // y position
            Float(normalizedBox.width),         // width
            Float(normalizedBox.height),        // height
            Float(aspectRatio),                 // aspect ratio
            Float(area),                        // area
            confidence,                         // OCR confidence
            Float(boundingBox.width)            // pixel width
        ]
        
        return createMLMultiArray(from: features, shape: [1, 8])
    }
    
    // MARK: - Bounding Box Utilities
    
    /// Calculate Intersection over Union (IoU) for two bounding boxes
    public static func calculateIoU(_ box1: CGRect, _ box2: CGRect) -> Float {
        let intersection = box1.intersection(box2)
        
        guard !intersection.isNull else { return 0.0 }
        
        let intersectionArea = intersection.width * intersection.height
        let unionArea = box1.width * box1.height + box2.width * box2.height - intersectionArea
        
        guard unionArea > 0 else { return 0.0 }
        
        return Float(intersectionArea / unionArea)
    }
    
    /// Apply Non-Maximum Suppression to bounding boxes
    public static func nonMaximumSuppression(
        boxes: [CGRect],
        scores: [Float],
        iouThreshold: Float = 0.5,
        scoreThreshold: Float = 0.3
    ) -> [Int] {
        
        // Filter by score threshold
        let validIndices = scores.enumerated().compactMap { index, score in
            score >= scoreThreshold ? index : nil
        }
        
        // Sort by score (descending)
        let sortedIndices = validIndices.sorted { scores[$0] > scores[$1] }
        
        var selectedIndices: [Int] = []
        var suppressed = Set<Int>()
        
        for index in sortedIndices {
            if suppressed.contains(index) { continue }
            
            selectedIndices.append(index)
            
            // Suppress overlapping boxes
            for otherIndex in sortedIndices {
                if otherIndex == index || suppressed.contains(otherIndex) { continue }
                
                let iou = calculateIoU(boxes[index], boxes[otherIndex])
                if iou > iouThreshold {
                    suppressed.insert(otherIndex)
                }
            }
        }
        
        return selectedIndices
    }
    
    // MARK: - Performance Utilities
    
    /// Measure execution time of a closure
    public static func measureTime<T>(_ operation: () throws -> T) rethrows -> (result: T, timeInterval: TimeInterval) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try operation()
        let timeInterval = CFAbsoluteTimeGetCurrent() - startTime
        return (result, timeInterval)
    }
    
    /// Async version of measureTime
    public static func measureTime<T>(_ operation: () async throws -> T) async rethrows -> (result: T, timeInterval: TimeInterval) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await operation()
        let timeInterval = CFAbsoluteTimeGetCurrent() - startTime
        return (result, timeInterval)
    }
    
    // MARK: - Memory Management
    
    /// Get memory usage of CVPixelBuffer
    public static func getPixelBufferMemorySize(_ pixelBuffer: CVPixelBuffer) -> Int {
        return CVPixelBufferGetBytesPerRow(pixelBuffer) * CVPixelBufferGetHeight(pixelBuffer)
    }
    
    /// Get memory usage of MLMultiArray
    public static func getMLMultiArrayMemorySize(_ multiArray: MLMultiArray) -> Int {
        let elementSize: Int
        switch multiArray.dataType {
        case .double:
            elementSize = MemoryLayout<Double>.size
        case .float32:
            elementSize = MemoryLayout<Float>.size
        case .int32:
            elementSize = MemoryLayout<Int32>.size
        case .float16:
            elementSize = MemoryLayout<Float>.size / 2
        @unknown default:
            elementSize = 4 // Assume 4 bytes
        }
        return multiArray.count * elementSize
    }
    
    /// Create optimized pixel buffer pool
    public static func createPixelBufferPool(
        width: Int,
        height: Int,
        pixelFormat: OSType = kCVPixelFormatType_32BGRA,
        maxBuffers: Int = 3
    ) -> CVPixelBufferPool? {
        
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: pixelFormat,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        
        let poolAttributes: [CFString: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey: maxBuffers,
            kCVPixelBufferPoolMaximumBufferAgeKey: 3.0
        ]
        
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            attributes as CFDictionary,
            &pool
        )
        
        guard status == kCVReturnSuccess else {
            logger.error("Failed to create pixel buffer pool: \(status)")
            return nil
        }
        
        return pool
    }
}

// MARK: - Extensions

extension MLMultiArray {
    
    /// Convenience subscript for easier access
    public subscript(indices: [Int]) -> NSNumber {
        get {
            return self[indices.map { NSNumber(value: $0) }]
        }
        set {
            self[indices.map { NSNumber(value: $0) }] = newValue
        }
    }
}

extension CGRect {
    
    /// Check if rectangle has valid dimensions for ML processing
    public var isValidForML: Bool {
        return width > 0 && height > 0 && !isInfinite && !isNull
    }
    
    /// Expand rectangle by a factor while keeping it centered
    public func expanded(by factor: CGFloat) -> CGRect {
        let newWidth = width * factor
        let newHeight = height * factor
        let deltaX = (newWidth - width) / 2
        let deltaY = (newHeight - height) / 2
        
        return CGRect(
            x: origin.x - deltaX,
            y: origin.y - deltaY,
            width: newWidth,
            height: newHeight
        )
    }
}

extension String {
    
    /// Calculate simple hash for text feature generation
    public var simpleHash: Int {
        return self.hash
    }
    
    /// Check if string matches Apple serial format pattern
    public var isAppleSerialFormat: Bool {
        let pattern = "^[A-Z0-9]{12}$"
        return range(of: pattern, options: .regularExpression) != nil
    }
}
