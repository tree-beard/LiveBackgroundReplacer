import MetalKit

final class MetalView: MTKView {
    init(device: MTLDevice) {
        super.init(frame: .zero, device: device)
        framebufferOnly = false
        colorPixelFormat = .bgra8Unorm
        isPaused = true
        enableSetNeedsDisplay = true
        autoResizeDrawable = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("Use init(device:)")
    }
}
