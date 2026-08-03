import CGtk4
import Foundation

/// Serves `org.kde.StatusNotifierItem` and registers it with the watcher.
///
/// Replaces `libayatana-appindicator-glib`, which was GPL-3 in an MIT project
/// and shipped in neither Fedora nor any Debian or Ubuntu release older than
/// sid / 25.10 — so no `.rpm` and no LTS `.deb` was possible while it stayed.
/// The interface below is copied from that library's own introspection XML,
/// so hosts see exactly what they saw before.
///
/// The object path is unchanged, which means `TrayMenuServer` keeps serving
/// `com.canonical.dbusmenu` on it and the `Menu` property keeps pointing at
/// the same place.
///
/// Main-loop thread only, like every other GLib wrapper here.
public final class StatusNotifierItemServer {
    private let connection: OpaquePointer
    private let objectPath: String
    private var state: StatusNotifierItemState
    private var registrationID: guint = 0
    private var watcherID: guint = 0
    private var nodeInfo: UnsafeMutablePointer<GDBusNodeInfo>?
    private let vtable = UnsafeMutablePointer<GDBusInterfaceVTable>.allocate(capacity: 1)

    public var onActivate: (@Sendable () -> Void)?
    public var onSecondaryActivate: (@Sendable () -> Void)?

    private static let interfaceName = "org.kde.StatusNotifierItem"
    private static let watcherName = "org.kde.StatusNotifierWatcher"
    private static let watcherPath = "/StatusNotifierWatcher"

    /// Verbatim from `libayatana-appindicator-glib.so.2`. Every property the
    /// model answers must appear here, and every signal emitted must be
    /// declared — `g_dbus_connection_emit_signal` validates against it.
    static let introspectionXML = """
    <node>
      <interface name="org.kde.StatusNotifierItem">
        <property name="Id" type="s" access="read" />
        <property name="Category" type="s" access="read" />
        <property name="Status" type="s" access="read" />
        <property name="IconName" type="s" access="read" />
        <property name="IconAccessibleDesc" type="s" access="read" />
        <property name="AttentionIconName" type="s" access="read" />
        <property name="AttentionAccessibleDesc" type="s" access="read" />
        <property name="Title" type="s" access="read" />
        <property name="IconThemePath" type="s" access="read" />
        <property name="Menu" type="o" access="read" />
        <property name="XAyatanaLabel" type="s" access="read" />
        <property name="XAyatanaLabelGuide" type="s" access="read" />
        <property name="XAyatanaOrderingIndex" type="u" access="read" />
        <property name="ToolTip" type="(sa(iiay)ss)" access="read" />
        <method name="Activate">
          <arg type="i" name="x" direction="in" />
          <arg type="i" name="y" direction="in" />
        </method>
        <method name="Scroll">
          <arg type="i" name="delta" direction="in" />
          <arg type="s" name="orientation" direction="in" />
        </method>
        <method name="SecondaryActivate">
          <arg type="i" name="x" direction="in" />
          <arg type="i" name="y" direction="in" />
        </method>
        <method name="XAyatanaSecondaryActivate">
          <arg type="u" name="timestamp" direction="in" />
        </method>
        <signal name="NewIcon" />
        <signal name="NewIconThemePath">
          <arg type="s" name="icon_theme_path" direction="out" />
        </signal>
        <signal name="NewAttentionIcon" />
        <signal name="NewStatus">
          <arg type="s" name="status" direction="out" />
        </signal>
        <signal name="XAyatanaNewLabel">
          <arg type="s" name="label" direction="out" />
          <arg type="s" name="guide" direction="out" />
        </signal>
        <signal name="NewTitle" />
        <signal name="NewToolTip" />
      </interface>
    </node>
    """

    public init(connection: OpaquePointer, objectPath: String, state: StatusNotifierItemState) {
        self.connection = connection
        self.objectPath = objectPath
        self.state = state
    }

    deinit {
        if self.watcherID != 0 { g_bus_unwatch_name(self.watcherID) }
        if self.registrationID != 0 {
            g_dbus_connection_unregister_object(self.connection, self.registrationID)
        }
        if let nodeInfo { g_dbus_node_info_unref(nodeInfo) }
        self.vtable.deallocate()
    }

    /// Registers the interface, then starts watching for the tray host.
    /// Returns false — after logging — when the bus rejects the object; the
    /// app keeps running without a tray icon rather than dying.
    @discardableResult
    public func register() -> Bool {
        var error: UnsafeMutablePointer<GError>?
        guard let nodeInfo = g_dbus_node_info_new_for_xml(Self.introspectionXML, &error) else {
            self.logError("g_dbus_node_info_new_for_xml", error)
            return false
        }
        self.nodeInfo = nodeInfo

        guard let interface = g_dbus_node_info_lookup_interface(nodeInfo, Self.interfaceName) else {
            FileHandle.standardError.write(Data(
                "codexbar: StatusNotifierItem interface missing from introspection XML\n".utf8))
            return false
        }

        self.vtable.pointee = GDBusInterfaceVTable()
        self.vtable.pointee.method_call = Self.methodCallThunk
        self.vtable.pointee.get_property = Self.getPropertyThunk
        self.vtable.pointee.set_property = nil

        // Unretained for the same reason as TrayMenuServer: the server and the
        // connection die together, and a retained box could never be released.
        let context = Unmanaged.passUnretained(self).toOpaque()
        self.registrationID = g_dbus_connection_register_object(
            self.connection,
            self.objectPath,
            interface,
            self.vtable,
            context,
            nil,
            &error)
        guard self.registrationID != 0 else {
            self.logError("g_dbus_connection_register_object", error)
            return false
        }

        // The watcher may not exist yet, and it may restart. Registering once
        // at startup would leave the icon missing in both cases — this is the
        // bookkeeping libayatana used to do.
        self.watcherID = g_bus_watch_name_on_connection(
            self.connection,
            Self.watcherName,
            // A flag enum, so the importer drops its zero-valued member and
            // G_BUS_NAME_WATCHER_FLAGS_NONE has no Swift name; see the same
            // note on GApplicationFlags in GtkApplication.
            GBusNameWatcherFlags(rawValue: 0),
            Self.watcherAppearedThunk,
            nil,
            context,
            nil)
        return true
    }

    // MARK: - Mutation

    public func setLabel(_ text: String) {
        guard self.state.label != text else { return }
        self.state.label = text
        self.emit(
            "XAyatanaNewLabel",
            payloadText: "(\(TrayMenuLayout.quote(text)), \(TrayMenuLayout.quote(self.state.labelGuide)))",
            payloadType: "(ss)")
    }

    public func setIcon(named name: String) {
        guard self.state.iconName != name else { return }
        self.state.iconName = name
        self.emit("NewIcon", payloadText: nil, payloadType: nil)
    }

    public func setTitle(_ title: String) {
        guard self.state.title != title else { return }
        self.state.title = title
        self.emit("NewTitle", payloadText: nil, payloadType: nil)
        self.emit("NewToolTip", payloadText: nil, payloadType: nil)
    }

    private func emit(_ signal: String, payloadText: String?, payloadType: String?) {
        guard self.registrationID != 0 else { return }
        var payload: OpaquePointer?
        if let payloadText, let payloadType {
            guard let parsed = TrayMenuLayout.parseVariant(text: payloadText, type: payloadType) else {
                return
            }
            payload = parsed
        }
        var error: UnsafeMutablePointer<GError>?
        g_dbus_connection_emit_signal(
            self.connection,
            nil,
            self.objectPath,
            Self.interfaceName,
            signal,
            payload,
            &error)
        // emit_signal sinks a floating ref; parseVariant hands back a full one.
        if let payload { g_variant_unref(payload) }
        if error != nil { self.logError("g_dbus_connection_emit_signal(\(signal))", error) }
    }

    // MARK: - Watcher registration

    private func registerWithWatcher() {
        // The spec lets the service argument be an object path, in which case
        // the sender's unique bus name is used — which is why the watcher lists
        // items as ":1.N/org/ayatana/appindicator/codexbar".
        guard let arguments = TrayMenuLayout.parseVariant(
            text: "(\(TrayMenuLayout.quote(self.objectPath)),)",
            type: "(s)")
        else {
            return
        }
        g_dbus_connection_call(
            self.connection,
            Self.watcherName,
            Self.watcherPath,
            Self.watcherName,
            "RegisterStatusNotifierItem",
            arguments, // call consumes the floating-or-full reference
            nil,
            GDBusCallFlags(rawValue: 0),
            -1,
            nil,
            nil,
            nil)
    }

    private static let watcherAppearedThunk: GBusNameAppearedCallback = { _, _, _, userData in
        guard let userData else { return }
        Unmanaged<StatusNotifierItemServer>.fromOpaque(userData)
            .takeUnretainedValue()
            .registerWithWatcher()
    }

    // MARK: - Vtable

    private static let methodCallThunk: GDBusInterfaceMethodCallFunc = {
        _, _, _, _, methodName, _, invocation, userData in
        guard let userData, let methodName, let invocation else { return }
        let server = Unmanaged<StatusNotifierItemServer>.fromOpaque(userData).takeUnretainedValue()
        switch String(cString: methodName) {
        case "Activate":
            server.onActivate?()
        case "SecondaryActivate", "XAyatanaSecondaryActivate":
            server.onSecondaryActivate?()
        case "Scroll":
            break // nothing is bound to scrolling
        default:
            g_dbus_method_invocation_return_dbus_error(
                invocation,
                "org.freedesktop.DBus.Error.UnknownMethod",
                "Unknown StatusNotifierItem method")
            return
        }
        g_dbus_method_invocation_return_value(invocation, nil)
    }

    private static let getPropertyThunk: GDBusInterfaceGetPropertyFunc = {
        _, _, _, _, propertyName, _, userData in
        guard let userData, let propertyName else { return nil }
        let server = Unmanaged<StatusNotifierItemServer>.fromOpaque(userData).takeUnretainedValue()
        let name = String(cString: propertyName)
        guard let text = server.state.propertyText(for: name),
              let type = server.state.propertyType(for: name)
        else {
            return nil
        }
        return TrayMenuLayout.parseVariant(text: text, type: type)
    }

    private func logError(_ context: String, _ error: UnsafeMutablePointer<GError>?) {
        let message = error.map { String(cString: $0.pointee.message) } ?? "unknown error"
        FileHandle.standardError.write(Data("codexbar: \(context) failed: \(message)\n".utf8))
        if let error { g_error_free(error) }
    }

    // MARK: - Introspection, for the tests

    /// Reads the XML as text rather than walking `GDBusInterfaceInfo`'s
    /// null-terminated C arrays: the question these answer is "does the XML
    /// declare what the model claims", and text answers it without a second
    /// source of pointer bugs.
    private static func names(ofElement element: String) -> [String] {
        let pattern = "<\(element) name=\"([A-Za-z]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let xml = self.introspectionXML
        let range = NSRange(xml.startIndex..., in: xml)
        return regex.matches(in: xml, range: range).compactMap { match in
            Range(match.range(at: 1), in: xml).map { String(xml[$0]) }
        }
    }

    static func declaredPropertyNames() -> [String] { self.names(ofElement: "property") }
    static func declaredSignalNames() -> [String] { self.names(ofElement: "signal") }
    static func declaredMethodNames() -> [String] { self.names(ofElement: "method") }
}
