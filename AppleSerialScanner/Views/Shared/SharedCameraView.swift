import SwiftUI
import AVFoundation

#if os(iOS)
struct SharedCameraView: UIViewRepresentable {
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    func makeUIView(context: Context) -> CameraContainerView {
        let view = CameraContainerView()
        view.backgroundColor = .black
        
        if let previewLayer = previewLayer {
            view.setupPreviewLayer(previewLayer)
            AppLogger.camera.debug("[iOS] makeUIView - view.bounds: \(String(describing: view.bounds))")
            AppLogger.camera.debug("[iOS] Added previewLayer with frame: \(String(describing: previewLayer.frame))")
        }
        
        return view
    }
    
    func updateUIView(_ uiView: CameraContainerView, context: Context) {
        if let previewLayer = previewLayer {
            uiView.updatePreviewLayerFrame(previewLayer)
            AppLogger.camera.debug("[iOS] updateUIView - previewLayer.frame: \(String(describing: previewLayer.frame)), uiView.bounds: \(String(describing: uiView.bounds))")
        }
    }
}

class CameraContainerView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasValidBounds = false
    
    func setupPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        // Remove existing layer if any
        previewLayer?.removeFromSuperlayer()
        
        previewLayer = layer
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        
        // Set initial frame
        updatePreviewLayerFrame(layer)
    }
    
    func updatePreviewLayerFrame(_ layer: AVCaptureVideoPreviewLayer) {
        // Ensure we have valid bounds before setting frame
        guard bounds.width > 0 && bounds.height > 0 else {
            AppLogger.camera.debug("[iOS] Skipping frame update - invalid bounds: \(String(describing: bounds))")
            return
        }
        
        // Track when we first get valid bounds
        if !hasValidBounds {
            hasValidBounds = true
            AppLogger.camera.debug("[iOS] First valid bounds detected: \(String(describing: bounds))")
        }
        
        // Skip update if frame hasn't changed to prevent recursive updates
        if layer.frame == bounds {
            return
        }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = bounds
        CATransaction.commit()
        
        AppLogger.camera.debug("[iOS] Updated previewLayer.frame to: \(String(describing: layer.frame))")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Update preview layer frame when the view layout changes
        if let previewLayer = previewLayer {
            updatePreviewLayerFrame(previewLayer)
        }
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        
        // Force layout update when view is added to window
        if window != nil, let previewLayer = previewLayer {
            DispatchQueue.main.async {
                self.updatePreviewLayerFrame(previewLayer)
            }
        }
    }
}

#else
struct SharedCameraView: NSViewRepresentable {
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    func makeNSView(context: Context) -> CameraContainerNSView {
        let view = CameraContainerNSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        
        if let previewLayer = previewLayer {
            view.setupPreviewLayer(previewLayer)
            AppLogger.camera.debug("[macOS] makeNSView - view.bounds: \(String(describing: view.bounds))")
            AppLogger.camera.debug("[macOS] Added previewLayer with frame: \(String(describing: previewLayer.frame))")
        }
        
        return view
    }
    
    func updateNSView(_ nsView: CameraContainerNSView, context: Context) {
        if let previewLayer = previewLayer {
            nsView.updatePreviewLayerFrame(previewLayer)
            AppLogger.camera.debug("[macOS] updateNSView - previewLayer.frame: \(String(describing: previewLayer.frame)), nsView.bounds: \(String(describing: nsView.bounds))")
        }
    }
}

class CameraContainerNSView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasValidBounds = false
    
    func setupPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
        // Remove existing layer if any
        previewLayer?.removeFromSuperlayer()
        
        previewLayer = layer
        layer.videoGravity = .resizeAspectFill
        self.layer?.addSublayer(layer)
        
        // Set initial frame
        updatePreviewLayerFrame(layer)
    }
    
    func updatePreviewLayerFrame(_ layer: AVCaptureVideoPreviewLayer) {
        // Ensure we have valid bounds before setting frame
        guard bounds.width > 0 && bounds.height > 0 else {
            AppLogger.camera.debug("[macOS] Skipping frame update - invalid bounds: \(String(describing: bounds))")
            return
        }
        
        // Track when we first get valid bounds
        if !hasValidBounds {
            hasValidBounds = true
            AppLogger.camera.debug("[macOS] First valid bounds detected: \(String(describing: bounds))")
        }
        
        // Skip update if frame hasn't changed to prevent recursive updates
        if layer.frame == bounds {
            return
        }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = bounds
        CATransaction.commit()
        
        // Force immediate visual update
        DispatchQueue.main.async {
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
        }
        
        AppLogger.camera.debug("[macOS] Updated previewLayer.frame to: \(String(describing: layer.frame))")
    }
    
    override func layout() {
        super.layout()
        
        // Update preview layer frame when the view layout changes
        if let previewLayer = previewLayer {
            updatePreviewLayerFrame(previewLayer)
        }
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        // Force layout update when view is added to window
        if window != nil, let previewLayer = previewLayer {
            DispatchQueue.main.async {
                self.updatePreviewLayerFrame(previewLayer)
            }
        }
    }
}
#endif

// This typealias maintains compatibility with existing code
typealias CameraPreviewView = SharedCameraView
