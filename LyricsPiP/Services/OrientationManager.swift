import UIKit
import Combine

/// Drives the programmatic orientation changes behind the "rotate" buttons.
///
/// Modes:
/// - `.none`: normal auto-rotation (portrait + landscape both allowed).
/// - `.landscape` / `.portrait`: the app is *locked* to that orientation, so
///   the request holds even when the phone is physically the other way, and
///   even when the system rotation lock is on (`requestGeometryUpdate`
///   bypasses it — the whole point of the buttons).
///
/// To still honor "physically rotate to leave the forced orientation", we watch
/// the accelerometer-driven device orientation and release the lock back to
/// `.none` (snapping to the physical orientation) once the user turns the phone
/// the opposite way.
@MainActor
final class OrientationManager: ObservableObject {
    static let shared = OrientationManager()

    enum Forced {
        case none, landscape, portrait
    }

    @Published private(set) var forced: Forced = .none

    /// Read by `AppDelegate.application(_:supportedInterfaceOrientationsFor:)`.
    var supportedMask: UIInterfaceOrientationMask {
        switch forced {
        case .none: return [.portrait, .landscapeLeft, .landscapeRight]
        case .landscape: return .landscape
        case .portrait: return .portrait
        }
    }

    private init() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceOrientationChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    /// Force landscape (portrait screen's landscape button).
    func enterLandscape() {
        forced = .landscape
        apply(.landscape)
    }

    /// Force portrait (landscape view's back button).
    func enterPortrait() {
        forced = .portrait
        apply(.portrait)
    }

    @objc private func deviceOrientationChanged() {
        let device = UIDevice.current.orientation
        switch forced {
        case .landscape where device.isPortrait:
            // Physically turned upright while forced-landscape -> release.
            forced = .none
            apply(.portrait)
        case .portrait where device.isLandscape:
            // Physically turned sideways while forced-portrait -> release.
            forced = .none
            apply(.landscape)
        default:
            break
        }
    }

    /// Pushes the current `supportedMask` to the system and asks it to rotate to
    /// `orientations` now. iOS resolves the concrete orientation from the mask.
    private func apply(_ orientations: UIInterfaceOrientationMask) {
        guard let scene = Self.activeWindowScene() else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations), errorHandler: { error in
            let message = error.localizedDescription
            Task { @MainActor in DebugLog.shared.log("[Orientation] 回転要求に失敗: \(message)") }
        })
    }

    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
}
