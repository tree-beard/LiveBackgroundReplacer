import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMedia
import Vision

enum BackgroundMode {
    case original
    case blur(radius: Double)
    case image(CIImage)
}

/// Confined to the camera's serial processing queue, including mode changes.
final class FrameProcessor {
    struct Output {
        let image: CIImage
        let warning: String?
        let visionMilliseconds: Double
    }

    var mode: BackgroundMode = .original {
        didSet { cachedBackground = nil }
    }
    private var cachedBackground: (extent: CGRect, image: CIImage)?
    private let segmentationRequest: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()

    func process(_ sampleBuffer: CMSampleBuffer) -> Output? {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        let source = CIImage(cvPixelBuffer: buffer)
        if case .original = mode {
            return Output(image: source, warning: nil, visionMilliseconds: 0)
        }

        let start = ProcessInfo.processInfo.systemUptime
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([segmentationRequest])
            let milliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1_000
            guard let observation = segmentationRequest.results?.first else {
                return Output(image: source, warning: "Vision did not return a mask. Showing the original frame.", visionMilliseconds: milliseconds)
            }
            let mask = CIImage(cvPixelBuffer: observation.pixelBuffer)
            return Output(image: try composite(source: source, mask: mask), warning: nil, visionMilliseconds: milliseconds)
        } catch {
            return Output(image: source, warning: "Processing error: \(error.localizedDescription)",
                          visionMilliseconds: (ProcessInfo.processInfo.systemUptime - start) * 1_000)
        }
    }

    /// Composites the source with the selected background using the person mask.
    func composite(source: CIImage, mask: CIImage) throws -> CIImage {
        guard Self.valid(source.extent), Self.valid(mask.extent) else {
            throw ProcessingError.invalidExtent
        }

        let background: CIImage
        switch mode {
        case .original:
            return source
        case .blur(let radius):
            background = source.clampedToExtent()
                .applyingGaussianBlur(sigma: max(0, radius))
                .cropped(to: source.extent)
        case .image(let original):
            if let cachedBackground, cachedBackground.extent == source.extent {
                background = cachedBackground.image
            } else {
                background = try Self.aspectFill(original, in: source.extent)
                cachedBackground = (source.extent, background)
            }
        }

        let normalizedMask = mask.transformed(by: .init(translationX: -mask.extent.minX, y: -mask.extent.minY))
            .transformed(by: .init(scaleX: source.extent.width / mask.extent.width,
                                  y: source.extent.height / mask.extent.height))
            .transformed(by: .init(translationX: source.extent.minX, y: source.extent.minY))
        let filter = CIFilter.blendWithMask()
        filter.inputImage = source
        filter.backgroundImage = background
        filter.maskImage = normalizedMask

        guard let result = filter.outputImage else {
            throw ProcessingError.noOutput
        }
        return result.cropped(to: source.extent)
    }

    static func aspectFill(_ image: CIImage, in target: CGRect) throws -> CIImage {
        guard valid(image.extent), valid(target) else {
            throw ProcessingError.invalidExtent
        }

        let scale = max(target.width / image.extent.width, target.height / image.extent.height)
        let scaled = image.transformed(by: .init(scaleX: scale, y: scale))
        return scaled.transformed(by: .init(translationX: target.midX - scaled.extent.midX,
                                           y: target.midY - scaled.extent.midY)).cropped(to: target)
    }

    private static func valid(_ extent: CGRect) -> Bool {
        !extent.isInfinite && !extent.isNull && !extent.isEmpty &&
        extent.origin.x.isFinite && extent.origin.y.isFinite &&
        extent.width.isFinite && extent.height.isFinite
    }

    private enum ProcessingError: LocalizedError {
        case invalidExtent, noOutput
        var errorDescription: String? {
            switch self {
            case .invalidExtent: return "Invalid image dimensions."
            case .noOutput: return "The filter did not return an image."
            }
        }
    }
}
