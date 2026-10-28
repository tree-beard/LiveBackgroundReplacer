import MetalKit
import CoreImage
import Synchronization

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
    private struct FrameState {
        var pendingImage: CIImage?
        var deliveryScheduled = false
        var acceptingFrames = false
    }

    private let frameState = Mutex(FrameState())
    private var inFlightCount = 0 // Main thread only, including completion updates.
    private var redrawPending = false
    var mirrored = true {
        didSet { view?.needsDisplay = true }
    }

    init(device: MTLDevice) throws {
        guard let queue = device.makeCommandQueue() else {
            throw RendererError.unavailable
        }
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
        frameState.withLock { state in
            state.acceptingFrames = accepting
            if !accepting { state.pendingImage = nil }
        }
        if !accepting {
            image = nil
            renderedImage = nil
            view?.needsDisplay = true
        }
    }

    func submit(_ frame: CIImage) {
        let schedule = frameState.withLock { state in
            guard state.acceptingFrames else {
                return false
            }
            state.pendingImage = frame
            let schedule = !state.deliveryScheduled
            state.deliveryScheduled = true
            return schedule
        }
        guard schedule else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            let latest = self.frameState.withLock { state in
                let latest = state.pendingImage
                state.pendingImage = nil
                state.deliveryScheduled = false
                return latest
            }
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
        guard let renderedImage else {
            return nil
        }
        return context.pngRepresentation(of: renderedImage, format: .RGBA8,
                                         colorSpace: colorSpace, options: [:])
    }

    func draw(in view: MTKView) {
        guard inFlightCount < 3 else {
            redrawPending = true
            return
        }

        guard view.drawableSize.width > 0, view.drawableSize.height > 0,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

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
        commandBuffer.addCompletedHandler { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.inFlightCount -= 1
                guard self.redrawPending else {
                    return
                }
                self.redrawPending = false
                self.view?.needsDisplay = true
            }
        }

        inFlightCount += 1
        commandBuffer.commit()
        renderedImage = frameToCapture
    }

    enum RendererError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Metal is not available on this device." }
    }
}
