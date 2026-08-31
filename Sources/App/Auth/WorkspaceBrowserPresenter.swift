import AppKit
import CursorBarAdapters
import Foundation

/// Opens the CLI-parity login URL in the default browser.
/// ASWebAuthenticationSession is unsuitable: completion is poll-only, not a callback URL scheme.
struct WorkspaceBrowserPresenter: BrowserPresenting {
    func present(loginURL: URL) async throws {
        let opened = await MainActor.run {
            NSWorkspace.shared.open(loginURL)
        }
        if !opened {
            throw CancellationError()
        }
    }
}
