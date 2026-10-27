import SwiftUI
import MetalKit

struct CameraViewRepresentable: NSViewRepresentable {
    let renderer: Renderer

    func makeCoordinator() -> Renderer { renderer }

    func makeNSView(context: Context) -> MetalView {
        let view = MetalView(device: renderer.device)
        renderer.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: MetalView, context: Context) {}

    static func dismantleNSView(_ nsView: MetalView, coordinator: Renderer) {
        coordinator.detach()
    }
}
