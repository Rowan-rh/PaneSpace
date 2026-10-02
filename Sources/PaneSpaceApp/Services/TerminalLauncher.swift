import AppKit
import Foundation

/// The part of `NSWorkspace` this app needs to hand a folder to a chosen application. Keeping the
/// launch boundary behind this protocol is what lets the tests assert which application was asked
/// to open a directory without an application ever starting.
@MainActor
protocol ApplicationLaunching: AnyObject {
    /// Where the application is installed, or nil when it is not on this Mac.
    func applicationURL(forBundleIdentifier identifier: String) -> URL?
    /// Hands `url` to the application at `applicationURL`, reporting whether the launch was
    /// accepted. `NSWorkspace` reports a refusal only through its completion handler, so the
    /// caller learns about a failure instead of treating a silent no-op as success.
    func open(
        _ url: URL,
        withApplicationAt applicationURL: URL,
        configuration: NSWorkspace.OpenConfiguration,
        completion: @escaping @MainActor (Bool) -> Void
    )
}

/// `NSWorkspace` is final, so conformance is added to a small forwarding class instead of the
/// shared instance.
@MainActor
final class WorkspaceApplicationLauncher: ApplicationLaunching {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func applicationURL(forBundleIdentifier identifier: String) -> URL? {
        workspace.urlForApplication(withBundleIdentifier: identifier)
    }

    func open(
        _ url: URL,
        withApplicationAt applicationURL: URL,
        configuration: NSWorkspace.OpenConfiguration,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        workspace.open([url], withApplicationAt: applicationURL, configuration: configuration) { _, error in
            let succeeded = error == nil
            // The handler is not main-actor isolated, so the hop is explicit rather than assumed.
            Task { @MainActor in completion(succeeded) }
        }
    }
}

/// Opens a folder in a terminal application.
///
/// Otty is preferred because it is the terminal this project is developed against, and it declares
/// folders as a document type it can open, so handing it the directory is enough. Terminal is the
/// fallback, so the command still works on a Mac that does not have Otty installed.
@MainActor
struct TerminalLauncher {
    /// Otty's bundle identifier, checked before the system Terminal.
    static let preferredBundleIdentifier = "io.appmakes.otty"
    static let fallbackBundleIdentifier = "com.apple.Terminal"

    /// The terminals this command can use, in preference order.
    static let bundleIdentifiers = [preferredBundleIdentifier, fallbackBundleIdentifier]

    private let launcher: any ApplicationLaunching

    init(launcher: any ApplicationLaunching = WorkspaceApplicationLauncher()) {
        self.launcher = launcher
    }

    /// Opens `directory` in the first available terminal. The completion receives the bundle
    /// identifier of the application that was asked to open it, which is what makes the preference
    /// order observable, or nil when no terminal could be launched.
    func open(_ directory: URL, completion: @escaping @MainActor (String?) -> Void) {
        guard let terminal = availableTerminal() else {
            completion(nil)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        launcher.open(directory, withApplicationAt: terminal.application, configuration: configuration) { succeeded in
            completion(succeeded ? terminal.bundleIdentifier : nil)
        }
    }

    /// Where the first available terminal is installed, or nil when none of them are. The bundle
    /// identifier travels with the URL because a file URL does not carry one.
    func availableTerminal() -> (bundleIdentifier: String, application: URL)? {
        for identifier in Self.bundleIdentifiers {
            if let application = launcher.applicationURL(forBundleIdentifier: identifier) {
                return (identifier, application)
            }
        }
        return nil
    }

    /// The identifier of the terminal that would be used, without launching anything.
    func availableTerminalIdentifier() -> String? {
        availableTerminal()?.bundleIdentifier
    }
}

enum TerminalLauncherError: LocalizedError, Equatable, Sendable {
    case noTerminalAvailable
    case directoryUnavailable
    case launchFailed

    var errorDescription: String? {
        switch self {
        case .noTerminalAvailable:
            return L10n.text("No terminal application could be opened.")
        case .directoryUnavailable:
            return L10n.text("This folder is currently unavailable.")
        case .launchFailed:
            return L10n.text("The terminal could not be opened.")
        }
    }
}
