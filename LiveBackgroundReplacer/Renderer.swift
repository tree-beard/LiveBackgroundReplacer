import MetalKit
import CoreImage

/// View attachment and drawing happen on the main thread. submit is thread safe
/// and holds at most one pending frame when the UI cannot keep up.
final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let context: CIContext
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private weak var view: MTKView?
    private var image: CIImage?
    private var renderedImage: CIImage?
    private let frameLock = NSLock()
    private let inFlight = DispatchSemaphore(value: 3)
    private var pendingImage: CIImage?
    private var deliveryScheduled = false
    private var acceptingFrames = false
    private var redrawPending = false
    var mirrored = true {
        didSet { view?.needsDisplay = true }
    }

    init(device: MTLDevice) throws {
        guard let queue = device.makeCommandQueue() else { throw RendererError.unavailable }
        self.device = device
        commandQueue = queue
        context = CIContext(mtlDevice: device)
        super.init()
    }

    func attach(to view: MTKView) {
        self.view = view
        view.delegate = self
        view.needsDisplay = true
    }

    func detach() {
        view?.delegate = nil
        view = nil
    }

    func setAcceptingFrames(_ accepting: Bool) {
        frameLock.lock()
        acceptingFrames = accepting
        if !accepting { pendingImage = nil }
        frameLock.unlock()
        if !accepting {
            image = nil
            renderedImage = nil
            view?.needsDisplay = true
        }
    }

    func submit(_ frame: CIImage) {
        frameLock.lock()
        guard acceptingFrames else { frameLock.unlock(); return }
        pendingImage = frame
        let schedule = !deliveryScheduled
        deliveryScheduled = true
        frameLock.unlock()
        guard schedule else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.frameLock.lock()
            let latest = self.pendingImage
            self.pendingImage = nil
            self.deliveryScheduled = false
            self.frameLock.unlock()
            if let latest {
                self.image = latest
                self.view?.needsDisplay = true
            }
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        view.needsDisplay = true
    }

    /// Capture the last rendered composite at camera resolution, without UI or letterboxing.
    /// Called on the main thread, before the save dialog opens.
    func snapshotPNG() -> Data? {
        guard let renderedImage else { return nil }
        return context.pngRepresentation(of: renderedImage, format: .RGBA8,
                                         colorSpace: colorSpace, options: [:])
    }

    func draw(in view: MTKView) {
        guard inFlight.wait(timeout: .now()) == .success else {
            redrawPending = true
            return
        }
        var submitted = false
        defer { if !submitted { inFlight.signal() } }
        guard view.drawableSize.width > 0, view.drawableSize.height > 0,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        let bounds = CGRect(x: 0, y: 0, width: drawable.texture.width, height: drawable.texture.height)
        let black = CIImage(color: .black).cropped(to: bounds)
        var output = black
        var frameToCapture: CIImage?
        if var image, image.extent.width > 0, image.extent.height > 0 {
            if mirrored { image = image.transformed(by: .init(scaleX: -1, y: 1)) }
            frameToCapture = image.transformed(by: .init(translationX: -image.extent.minX,
                                                        y: -image.extent.minY))
            let scale = min(bounds.width / image.extent.width, bounds.height / image.extent.height)
            let scaled = image.transformed(by: .init(scaleX: scale, y: scale))
            let centered = scaled.transformed(by: .init(translationX: bounds.midX - scaled.extent.midX,
                                                       y: bounds.midY - scaled.extent.midY))
            output = centered.composited(over: black).cropped(to: bounds)
        }
        context.render(output, to: drawable.texture, commandBuffer: commandBuffer,
                       bounds: bounds, colorSpace: colorSpace)
        commandBuffer.present(drawable)
        let semaphore = inFlight
        commandBuffer.addCompletedHandler { [weak self] _ in
            semaphore.signal()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.redrawPending else { return }
                self.redrawPending = false
                self.view?.needsDisplay = true
            }
        }
        submitted = true
        commandBuffer.commit()
        renderedImage = frameToCapture
    }

    enum RendererError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Metal is not available on this device." }
    }
}
