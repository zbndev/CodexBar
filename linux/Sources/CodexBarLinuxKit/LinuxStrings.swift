import Foundation

/// Strings with no upstream macOS key because the control is Linux-only.
/// They are English until translations are contributed; every locale
/// overlays the upstream catalog on English, so these always resolve.
public enum LinuxStrings {
    public static let english: [String: String] = [
        "linux.settings.title": "Settings",
        "linux.settings.loading": "Loading…",
        "linux.settings.enabled": "Enabled",
        "linux.settings.usageSource": "Usage source",
        "linux.settings.cookieSource": "Cookie source",
        "linux.settings.cookieHeader": "Cookie header",
        "linux.settings.tray": "Tray",
        "linux.settings.popup": "Popup",
        "linux.settings.tokenAccounts": "Token accounts",
        "linux.settings.quotaWarnings": "Quota warnings",
        "linux.settings.hooks": "Hook rules",
        "linux.settings.open": "Open",
        "linux.settings.add": "Add",
        "linux.settings.remove": "Remove",
        "linux.settings.systemLanguage": "System language",
        "linux.settings.saved": "Saved",
        "linux.settings.useGlobal": "Use global defaults",
        "linux.login.cancel": "Cancel",
        "linux.login.preparing": "Preparing…",
        "linux.login.waitingForBrowser": "Finish signing in in the window that just opened.",
        "linux.login.awaitingCode": "Paste the code from the provider page.",
        "linux.login.exchanging": "Exchanging the code…",
        "linux.login.saving": "Saving…",
        "linux.login.finished": "Signed in.",
        "linux.login.enterCodeAt": "Enter this code at",
    ]
}
