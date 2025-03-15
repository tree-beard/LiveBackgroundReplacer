//
//  CameraView.swift
//  LiveBackgroundReplacer
//
//  Created by David Arakelyan on 21.08.2024.
//

import Foundation
import SwiftUI
import MetalKit

struct CameraView: NSViewRepresentable {

    func makeCoordinator() -> Renderer {
        return Renderer()
    }

    func makeNSView(context: NSViewRepresentableContext<CameraView>) -> MTKView {
        let mtkView = MetalView()
        mtkView.setRenderer(context.coordinator)
        return mtkView
    }

    func updateNSView(_ nsView: NSViewType, context: Context) {

    }
}
