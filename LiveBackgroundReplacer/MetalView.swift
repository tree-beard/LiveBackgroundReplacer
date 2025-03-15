//
//  MetalView.swift
//  LiveBackgroundReplacer
//
//  Created by David Arakelyan on 21.08.2024.
//

import Foundation
import MetalKit

class MetalView: MTKView {

    var cameraController : VideoCameraController?

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init() {
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        self.preferredFramesPerSecond = 30
        self.enableSetNeedsDisplay = true
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.device = metalDevice
        }
        self.framebufferOnly = false
        self.drawableSize = self.frame.size
        self.enableSetNeedsDisplay = true
        self.isPaused = false
        self.colorPixelFormat = .rgba8Unorm
        self.cameraController = VideoCameraController(FrameProcessor())
    }

    public func setRenderer(_ renderer: Renderer?) {
        self.delegate = renderer
        let frameProcessor = cameraController?.frameProcessor
        frameProcessor?.delegate = renderer
    }
}
