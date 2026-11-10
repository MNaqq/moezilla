import Foundation
import GeckoView

/// Official signed uBlock Origin package from Mozilla Add-ons, bundled so
/// blocking works on the first launch even without an internet connection.
/// The user can disable it under Settings > Add-ons; this installer does not
/// re-enable an existing disabled installation.
@MainActor
enum BuiltInAdBlocking {
    static let extensionID = "uBlock0@raymondhill.net"
    static let signedPackageName = "uBlockOrigin"
    private(set) static var installing = false

    static func ensureInstalled() async {
        guard !installing else { return }
        let runtime = AddonRuntime.shared
        do {
            if try await runtime.list().contains(where: { $0.id == extensionID }) {
                return
            }
            guard let location = Bundle.main.url(forResource: signedPackageName, withExtension: "xpi") else {
                NSLog("Moezilla: uBlock Origin signed XPI isn't packaged")
                return
            }
            installing = true
            defer { installing = false }
            let installed = try await runtime.install(
                url: location.absoluteString,
                installMethod: .manager
            )
            guard installed.id == extensionID else {
                NSLog("Moezilla: unexpected uBlock extension ID: %@", installed.id)
                return
            }
            NSLog("Moezilla: built-in uBlock Origin installed: %@", installed.metaData.version ?? "unknown")
            // Private browsing should get the same first-party privacy blocking.
            if installed.metaData.incognito != .notAllowed {
                _ = try? await runtime.setAllowedInPrivateBrowsing(installed, allowed: true)
            }
        } catch {
            // A transient Gecko initialization error should not prevent the
            // browser from launching. Retrying on the next startup is safe.
            NSLog("Moezilla: built-in uBlock Origin install failed: %@", error.localizedDescription)
        }
    }

    static func approval(for prompt: AddonPermissionPrompt) -> AddonPermissionPromptResponse? {
        guard installing, prompt.kind == .install,
              prompt.addon.id == extensionID else { return nil }
        return AddonPermissionPromptResponse(allow: true)
    }
}
