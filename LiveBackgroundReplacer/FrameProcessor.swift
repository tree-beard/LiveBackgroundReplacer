//
//  FrameProcessor.swift
//  LiveBackgroundReplacer
//
//  Created by David Arakelyan on 21.08.2024.
//

import Foundation
import CoreImage
import Vision
import AppKit


protocol FrameProcessorDelegate: AnyObject {
    func update(_ frame: CIImage)
}

class FrameProcessor: NSObject {

    weak var delegate: FrameProcessorDelegate?
    var blurBackground: Bool = false
    var sourceCIImage: CIImage?
    var backgroundCIImage: CIImage?
    var backgroundImage: NSImage?
    var sourceFrame: CMSampleBuffer? {
        didSet {
            processFrame(sampleBuffer: sourceFrame!)
        }
    }

    private lazy var segmentationRequest: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest(completionHandler: segmentationCompletionHandler)
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()

    init(delegate: FrameProcessorDelegate? = nil) {
        super.init()
        self.blurBackground = false
        self.delegate = delegate
        self.backgroundImage = NSImage(named: "dirt_jump")
        guard let data = backgroundImage?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else {
            return
        }
        self.backgroundCIImage = CIImage(bitmapImageRep: bitmap)
    }

    private func processFrame(sampleBuffer: CMSampleBuffer) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        self.sourceCIImage = CIImage(cvPixelBuffer: imageBuffer as CVPixelBuffer)
        do {
            let handler = VNImageRequestHandler(ciImage: self.sourceCIImage!, options: [:])
            try handler.perform([self.segmentationRequest])
        } catch {
            debugPrint("Error performing vision image request: \(error.localizedDescription)")
        }
    }

    private func segmentationCompletionHandler(request: VNRequest?, error: Error?) {
        guard let result = request?.results?.first as? VNPixelBufferObservation else {
            return
        }
        let pixelBuffer = result.pixelBuffer
        var maskCIImage = CIImage(cvPixelBuffer: pixelBuffer, options: [:])
        var scaleX = sourceCIImage!.extent.width / maskCIImage.extent.width
        var scaleY = sourceCIImage!.extent.height / maskCIImage.extent.height
        maskCIImage = maskCIImage.transformed(by: .init(scaleX: scaleX, y: scaleY))

        var currentBackgroundImage: CIImage?
        if(blurBackground) {
            currentBackgroundImage = blurImage(inputImage: sourceCIImage!)
        }
        else {
            if(backgroundCIImage?.extent.size != sourceCIImage?.extent.size) {
                scaleX = sourceCIImage!.extent.width / backgroundCIImage!.extent.width
                scaleY = sourceCIImage!.extent.height / backgroundCIImage!.extent.height
                backgroundCIImage = backgroundCIImage!.transformed(by: .init(scaleX: scaleX, y: scaleY))
            }
            currentBackgroundImage = backgroundCIImage
        }
        let resultImage = blendImages(background: currentBackgroundImage!, foreground: sourceCIImage!, mask: maskCIImage)

        DispatchQueue.main.async {
            self.delegate?.update(resultImage!)
        }
    }

    private func blendImages(background: CIImage, foreground: CIImage, mask: CIImage) -> CIImage? {
        // Blend the original, background, and mask images.
        let blendFilter = CIFilter(name: "CIBlendWithMask")
        blendFilter?.setValue(background, forKey: kCIInputBackgroundImageKey)
        blendFilter?.setValue(foreground, forKey: kCIInputImageKey)
        blendFilter?.setValue(mask, forKey: kCIInputMaskImageKey)
        return blendFilter!.outputImage
    }

    private func blurImage(inputImage: CIImage) -> CIImage? {
        let blurFilter = CIFilter(name: "CIGaussianBlur")
        blurFilter?.setValue(inputImage, forKey: kCIInputImageKey)
        blurFilter?.setValue(15, forKey: kCIInputRadiusKey)

        let cropFilter = CIFilter(name: "CICrop")
        cropFilter!.setValue(blurFilter!.outputImage, forKey: kCIInputImageKey)
        cropFilter!.setValue(CIVector(cgRect: inputImage.extent), forKey: "inputRectangle")

        return cropFilter?.outputImage
    }
}
