import SwiftUI
import AVFoundation

#if os(iOS)
struct SharedCameraView: UIViewRepresentable {
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    func makeUIView(context: Context) -> CameraContainerView {
        let view = CameraContainerView()
        view.backgroundColor = .black
        
        if let previewLayer = self.previewLayer {
            view.setupPreviewLayer(previewLayer)
            print("[CameraView] makeUIView - view.bounds: \(view.bounds)")
            print("[CameraView] Added previewLayer with frame: \(previewLayer.frame)")
        }
        
        return view
    }
    
    func updateUIView(_ uiView: CameraContainerView, context: Context) {
        if let previewLayer = self.previewLayer {
            uiView.updatePreviewLayerFrame(previewLayer)
            print("[CameraView] updateUIView - previewLayer.frame: \(previewLayer.frame), uiView.bounds: \(uiView.bounds)")
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
            print("[CameraView] Skipping frame update - invalid bounds: \(bounds)")
            return
        }
        
        // Track when we first get valid bounds
        if !hasValidBounds {
            hasValidBounds = true
            print("[CameraView] First valid bounds detected: \(bounds)")
        }
        
        // Skip update if frame hasn't changed to prevent recursive updates
        if layer.frame == bounds {
            return
        }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = bounds
        CATransaction.commit()
        
        print("[CameraView] Updated previewLayer.frame to: \(layer.frame)")
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
        
        if let previewLayer = self.previewLayer {
            view.setupPreviewLayer(previewLayer)
            print("[CameraView] makeNSView - view.bounds: \(view.bounds)")
            print("[CameraView] Added previewLayer with frame: \(previewLayer.frame)")
        }
        
        return view
    }
    
    func updateNSView(_ nsView: CameraContainerNSView, context: Context) {
        if let previewLayer = self.previewLayer {
            nsView.updatePreviewLayerFrame(previewLayer)
            print("[CameraView] updateNSView - previewLayer.frame: \(previewLayer.frame), nsView.bounds: \(nsView.bounds)")
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
            print("[CameraView] Skipping frame update - invalid bounds: \(bounds)")
            return
        }
        
        // Track when we first get valid bounds
        if !hasValidBounds {
            hasValidBounds = true
            print("[CameraView] First valid bounds detected: \(bounds)")
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
        
        print("[CameraView] Updated previewLayer.frame to: \(layer.frame)")
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
