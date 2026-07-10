import SwiftUI
import AVFoundation

/// A UIView whose backing layer *is* the AVSampleBufferDisplayLayer used for
/// PIP. The system requires this layer to actually be part of a rendered
/// view hierarchy (not just floating in memory) before
/// `AVPictureInPictureController.isPictureInPicturePossible` will ever
/// become true — this was the missing piece causing PIP to silently refuse
/// to start.
final class PiPDisplayLayerContainerView: UIView {
    override class var layerClass: AnyClass {
        AVSampleBufferDisplayLayer.self
    }

    var displayLayer: AVSampleBufferDisplayLayer {
        // swiftlint:disable:next force_cast
        layer as! AVSampleBufferDisplayLayer
    }
}

/// Hosts the PIP display layer inside the SwiftUI view tree. Can be sized
/// tiny/near-invisible — it just needs to genuinely be part of the render
/// tree, not full-screen.
struct PiPHostView: UIViewRepresentable {
    let controller: PiPLyricsController

    func makeUIView(context: Context) -> PiPDisplayLayerContainerView {
        let view = PiPDisplayLayerContainerView()
        view.backgroundColor = .clear
        controller.attachDisplayLayer(view.displayLayer)
        return view
    }

    func updateUIView(_ uiView: PiPDisplayLayerContainerView, context: Context) {}
}
