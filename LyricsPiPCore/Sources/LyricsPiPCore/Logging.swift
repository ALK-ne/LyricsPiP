import Foundation

/// Minimal logging seam so services can be handed a logger instead of
/// reaching for the app's on-screen DebugLog singleton directly. MainActor
/// because every current caller and the DebugLog implementation already
/// live there (the log lines drive SwiftUI state).
@MainActor
public protocol LyricsPiPLogging: AnyObject {
    func log(_ message: String)
}
