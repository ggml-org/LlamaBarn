import AppKit
import OSLog
import Sentry

/// Suspends Sentry's app-hang reporting for the duration of an app-modal panel,
/// so an intentional block doesn't get reported as a freeze.
///
/// `runModal()` spins a nested run loop that blocks the main thread for as long
/// as the user reads the dialog. Sentry's V1 hang tracker -- the only one
/// available on macOS (V2, which classifies these correctly, is iOS/tvOS only)
/// -- can't distinguish that from a hang, so it reports "App hanging for at
/// least 2000 ms" every time a user lingers on an alert. That's pure noise, and
/// historically our single largest source of app-hang events. Sentry considers
/// the root cause unfixable on macOS and points at `pauseAppHangTracking()` as
/// the supported mitigation, which is what we do here.
///
/// Wrap the *whole* modal -- construction included, not just the `runModal()`
/// call. Building an `NSAlert` or `NSOpenPanel` loads a nib and creates a
/// window, and on a loaded machine that alone can exceed the 2s threshold. An
/// earlier version wrapped only `runModal()` and so kept reporting hangs
/// attributed to `NSAlert.init`.
enum ModalPresentation {
    private static let log = Logger(subsystem: Logging.subsystem, category: "ModalPresentation")

    // Modals can nest (an alert raised from an open panel), but the SDK's
    // pause/resume is a plain on/off switch -- so we count depth and let only
    // the outermost presentation toggle it. Without the count, an inner modal
    // finishing would resume tracking while the outer one is still on screen.
    // Only ever touched from the main actor, via `run(_:)`.
    private static var depth = 0

    /// Presents a modal with app-hang reporting suspended for its duration.
    ///
    /// `body` should both build and run the panel -- see the note above on why
    /// construction has to be inside the wrapper.
    @MainActor
    @discardableResult
    static func run<T>(_ body: () -> T) -> T {
        depth += 1
        if depth == 1 {
            SentrySDK.pauseAppHangTracking()
        }
        log.debug("Modal presentation begin (depth now \(depth, privacy: .public))")

        defer {
            depth -= 1
            if depth == 0 {
                SentrySDK.resumeAppHangTracking()
            }
            log.debug("Modal presentation end (depth now \(depth, privacy: .public))")
        }
        return body()
    }
}
