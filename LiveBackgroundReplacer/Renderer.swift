//
//  Renderer.swift
//  LiveBackgroundReplacer
//
//  Created by David Arakelyan on 21.08.2024.
//

import Foundation
import MetalKit
import CoreGraphics
import CoreImage

class Renderer: NSObject, MTKViewDelegate, FrameProcessorDelegate {

    private var metalDevice: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var context: CIContext!
    private var image: CIImage!
    private let colorSpace = CGColorSpaceCreateDeviceRGB()


    override init() {

        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.metalDevice = metalDevice
        }

        self.context = CIContext(mtlDevice: metalDevice)
        self.commandQueue = self.metalDevice.makeCommandQueue()

        super.init()
    }

    func update(_ frame: CIImage) {
        image = frame
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {

    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else {
            return
        }

        guard let image = image else {
            return
        }

        // A buffer to store all commands
        let commandBuffer = commandQueue.makeCommandBuffer()
        // Describe the resources
        let renderPassDescriptor = view.currentRenderPassDescriptor
        renderPassDescriptor?.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        renderPassDescriptor?.colorAttachments[0].loadAction = .clear
        renderPassDescriptor?.colorAttachments[0].storeAction = .store
        let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor!)
        renderEncoder?.endEncoding()

        let drawableSize = drawable.layer.drawableSize
        let widthScale = drawableSize.width / image.extent.width
        let heightScale = drawableSize.height / image.extent.height

        let scale = min(widthScale, heightScale)
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let xPos = drawableSize.width / 2 - scaledImage.extent.width / 2
        let yPos = drawableSize.height / 2 - scaledImage.extent.height / 2

        let bounds = CGRect(x: -xPos, y: -yPos, width: drawableSize.width, height: drawableSize.height)

        context.render(scaledImage,
                        to: drawable.texture,
                        commandBuffer: commandBuffer,
                        bounds: bounds,
                        colorSpace: colorSpace)

        commandBuffer?.present(drawable)
        commandBuffer?.commit()
    }
}
