import CGtk4
import CodexBarCore
import Foundation

/// A window showing the provider's own site so the user can sign in, with a
/// button that saves the resulting session.
///
/// Nothing about the sign-in is interpreted: no form is filled, no password is
/// read, no page script is injected. The window is a browser, and the only
/// thing taken from it is the cookie header for the configured URIs.
///
/// Finishing is manual on purpose. Auto-detecting "logged in" means guessing
/// from cookie presence, and a cookie set before the sign-in completes would
/// save a useless half-session.
public final class CookieLoginWindow: @unchecked Sendable {
    private let window: GtkWindow
    private let webView: WebView
    private let entry: CookieLoginEntry
    private let onFinish: @Sendable (String?) -> Void

    fileprivate final class ButtonBox {
        let work: () -> Void
        init(_ work: @escaping () -> Void) { self.work = work }
    }

    /// - Parameter onFinish: the harvested cookie header, or nil when the user
    ///   cancelled or nothing usable was collected. Called on the main loop.
    public init(
        application: GtkApplication,
        providerName: String,
        entry: CookieLoginEntry,
        onFinish: @escaping @Sendable (String?) -> Void)
    {
        self.entry = entry
        self.onFinish = onFinish
        self.window = GtkWindow(
            application: application,
            title: "Sign in to \(providerName)",
            width: 980,
            height: 760)
        self.webView = WebView(
            policy: .anyHTTPS,
            networkSession: WebView.ephemeralNetworkSession())

        guard let column = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0),
              let bar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8),
              let hint = gtk_label_new("Sign in, then click Save session."),
              let save = gtk_button_new_with_label("Save session"),
              let cancel = gtk_button_new_with_label("Cancel")
        else {
            fatalError("GTK returned NULL while building the cookie login window")
        }

        let viewWidget = UnsafeMutablePointer<_GtkWidget>(self.webView.widgetPointer)
        gtk_widget_set_hexpand(viewWidget, 1)
        gtk_widget_set_vexpand(viewWidget, 1)
        gtk_box_append(UnsafeMutablePointer<_GtkBox>(OpaquePointer(column)), viewWidget)

        gtk_widget_set_margin_start(bar, 12)
        gtk_widget_set_margin_end(bar, 12)
        gtk_widget_set_margin_top(bar, 8)
        gtk_widget_set_margin_bottom(bar, 8)
        gtk_widget_set_hexpand(hint, 1)
        // GtkLabel is a final type, so it imports as OpaquePointer — unlike
        // GtkBox/GtkWidget, which are derivable and keep their `_`-tagged structs.
        gtk_label_set_xalign(OpaquePointer(hint), 0)
        gtk_box_append(UnsafeMutablePointer<_GtkBox>(OpaquePointer(bar)), hint)
        gtk_box_append(UnsafeMutablePointer<_GtkBox>(OpaquePointer(bar)), cancel)
        gtk_box_append(UnsafeMutablePointer<_GtkBox>(OpaquePointer(bar)), save)
        gtk_box_append(UnsafeMutablePointer<_GtkBox>(OpaquePointer(column)), bar)

        self.window.setChild(OpaquePointer(column))
        self.connect(button: OpaquePointer(cancel)) { [weak self] in self?.finish(header: nil) }
        self.connect(button: OpaquePointer(save)) { [weak self] in self?.save() }

        self.webView.load(url: entry.loginURL)
    }

    public func present() {
        self.window.present()
    }

    private func save() {
        // Hop to a task because reading cookies is async, then back to the
        // main loop before touching GTK again.
        Task { [weak self] in
            guard let self else { return }
            let header = await CookieHarvester.cookieHeader(
                webView: self.webView,
                uris: self.entry.cookieURLs,
                allowedNames: [])
            MainLoopDispatch.onMainLoop {
                guard let header,
                      ProviderLoginCatalog.validate(
                          header: header,
                          against: self.entry.requiredCookieNames)
                else {
                    // Leave the window open: the user is probably mid-sign-in.
                    FileHandle.standardError.write(Data(
                        "codexbar: no usable session cookie yet\n".utf8))
                    return
                }
                self.finish(header: header)
            }
        }
    }

    private func finish(header: String?) {
        self.window.hide()
        self.onFinish(header)
    }

    private func connect(button: OpaquePointer, work: @escaping () -> Void) {
        let box = Unmanaged.passRetained(ButtonBox(work))
        g_signal_connect_data(
            gpointer(button),
            "clicked",
            unsafeBitCast(Self.clickThunk, to: GCallback.self),
            box.toOpaque(),
            { data, _ in
                guard let data else { return }
                Unmanaged<ButtonBox>.fromOpaque(data).release()
            },
            GConnectFlags(rawValue: 0))
    }

    private static let clickThunk: @convention(c) (
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void = { _, data in
            guard let data else { return }
            Unmanaged<ButtonBox>.fromOpaque(data).takeUnretainedValue().work()
        }
}
