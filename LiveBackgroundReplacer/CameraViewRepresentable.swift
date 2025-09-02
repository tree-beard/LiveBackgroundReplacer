//
//  CameraView.swift
//  LiveBackgroundReplacer
//
//  Created by David Arakelyan on 21.08.2024.
//

import Foundation
import SwiftUI
import MetalKit

struct CameraViewRepresentable: NSViewRepresentable {

    func makeNSView(context: NSViewRepresentableContext<CameraViewRepresentable>) -> MTKView {
        let mtkView = MetalView()
        return mtkView
    }

    func updateNSView(_ nsView: NSViewType, context: Context) {

    }
}
