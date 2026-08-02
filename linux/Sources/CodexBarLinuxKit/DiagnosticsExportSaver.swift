import CGtk4
import Foundation

public final class DiagnosticsExportSaver: @unchecked Sendable {
    private let data: Data
    private var selfBox: Unmanaged<DiagnosticsExportSaver>?

    public init(data: Data) {
        self.data = data
    }

    public func present(from parent: GtkWindow) {
        guard let dialog = gtk_file_chooser_native_new(
            "Export CodexBar Diagnostics",
            UnsafeMutablePointer<_GtkWindow>(parent.pointer),
            GTK_FILE_CHOOSER_ACTION_SAVE,
            "Export",
            "Cancel")
        else { return }
        let box = Unmanaged.passRetained(self)
        self.selfBox = box
        g_signal_connect_data(
            gpointer(dialog),
            "response",
            unsafeBitCast(Self.responseThunk, to: GCallback.self),
            box.toOpaque(),
            { data, _ in
                guard let data else { return }
                Unmanaged<DiagnosticsExportSaver>.fromOpaque(data).release()
            },
            GConnectFlags(rawValue: 0))
        gtk_native_dialog_show(UnsafeMutablePointer<_GtkNativeDialog>(dialog))
    }

    private static let responseThunk: @convention(c) (
        UnsafeMutableRawPointer?, Int32, UnsafeMutableRawPointer?) -> Void = { dialog, response, data in
        guard let dialog, let data, response == GTK_RESPONSE_ACCEPT.rawValue else { return }
        let saver = Unmanaged<DiagnosticsExportSaver>.fromOpaque(data).takeUnretainedValue()
        guard let file = gtk_file_chooser_get_file(OpaquePointer(dialog)) else { return }
        defer { g_object_unref(UnsafeMutableRawPointer(file)) }
        guard let path = g_file_get_path(file) else { return }
        defer { g_free(path) }
        try? saver.write(to: URL(fileURLWithPath: String(cString: path)))
    }

    private func write(to destination: URL) throws {
        try PrivateFileWriter.write(self.data, to: destination)
    }
}
