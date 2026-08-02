import CGtk4
import Foundation

/// Serves `com.canonical.dbusmenu` on the object path libayatana already
/// exports for the tray item.
///
/// `libayatana-appindicator-glib` publishes its menu as a `GMenuModel` over
/// `org.gtk.Menus`, which no StatusNotifierItem host reads — hosts follow the
/// item's `Menu` property and speak dbusmenu to it. That property already
/// points at `/org/ayatana/appindicator/<id>`, so registering a second
/// interface on that same path is all that is missing. `g_dbus_connection_
/// register_object` registers per (path, interface), so this does not disturb
/// the library's own registration.
///
/// Main-loop thread only, like every other GLib wrapper here.
public final class TrayMenuServer {
    private let connection: OpaquePointer
    private let objectPath: String
    private let items: [TrayMenuItem]
    private let activate: @Sendable (String) -> Void
    private var registrationID: guint = 0
    private var revision: UInt32 = 1
    private var nodeInfo: UnsafeMutablePointer<GDBusNodeInfo>?
    private let vtable = UnsafeMutablePointer<GDBusInterfaceVTable>.allocate(capacity: 1)

    private static let interfaceName = "com.canonical.dbusmenu"

    /// Only the members hosts actually call. Signals are declared because
    /// `g_dbus_connection_emit_signal` validates the emitted signature against
    /// the registered interface.
    private static let introspectionXML = """
    <node>
      <interface name="com.canonical.dbusmenu">
        <property name="Version" type="u" access="read"/>
        <property name="TextDirection" type="s" access="read"/>
        <property name="Status" type="s" access="read"/>
        <property name="IconThemePath" type="as" access="read"/>
        <method name="GetLayout">
          <arg type="i" name="parentId" direction="in"/>
          <arg type="i" name="recursionDepth" direction="in"/>
          <arg type="as" name="propertyNames" direction="in"/>
          <arg type="u" name="revision" direction="out"/>
          <arg type="(ia{sv}av)" name="layout" direction="out"/>
        </method>
        <method name="GetGroupProperties">
          <arg type="ai" name="ids" direction="in"/>
          <arg type="as" name="propertyNames" direction="in"/>
          <arg type="a(ia{sv})" name="properties" direction="out"/>
        </method>
        <method name="GetProperty">
          <arg type="i" name="id" direction="in"/>
          <arg type="s" name="name" direction="in"/>
          <arg type="v" name="value" direction="out"/>
        </method>
        <method name="Event">
          <arg type="i" name="id" direction="in"/>
          <arg type="s" name="eventId" direction="in"/>
          <arg type="v" name="data" direction="in"/>
          <arg type="u" name="timestamp" direction="in"/>
        </method>
        <method name="AboutToShow">
          <arg type="i" name="id" direction="in"/>
          <arg type="b" name="needUpdate" direction="out"/>
        </method>
        <signal name="ItemsPropertiesUpdated">
          <arg type="a(ia{sv})" name="updatedProps" direction="out"/>
          <arg type="a(ias)" name="removedProps" direction="out"/>
        </signal>
        <signal name="LayoutUpdated">
          <arg type="u" name="revision" direction="out"/>
          <arg type="i" name="parent" direction="out"/>
        </signal>
        <signal name="ItemActivationRequested">
          <arg type="i" name="id" direction="out"/>
          <arg type="u" name="timestamp" direction="out"/>
        </signal>
      </interface>
    </node>
    """

    /// - Parameter activate: invoked with a `GAction` name when a host reports
    ///   a click. Called on the main loop thread.
    public init(
        connection: OpaquePointer,
        objectPath: String,
        items: [TrayMenuItem],
        activate: @escaping @Sendable (String) -> Void)
    {
        self.connection = connection
        self.objectPath = objectPath
        self.items = items
        self.activate = activate
    }

    deinit {
        if self.registrationID != 0 {
            g_dbus_connection_unregister_object(self.connection, self.registrationID)
        }
        if let nodeInfo { g_dbus_node_info_unref(nodeInfo) }
        self.vtable.deallocate()
    }

    /// Registers the interface. Returns false — after logging — when the bus
    /// rejects it; the tray icon still works, only its menu stays empty, so
    /// this is never fatal.
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
                "codexbar: dbusmenu interface missing from introspection XML\n".utf8))
            return false
        }

        self.vtable.pointee = GDBusInterfaceVTable()
        self.vtable.pointee.method_call = Self.methodCallThunk
        self.vtable.pointee.get_property = Self.getPropertyThunk
        self.vtable.pointee.set_property = nil

        // Unretained: the server outlives the connection in practice (both die
        // with the process), and a retained box would leak by construction
        // because unregistering happens in deinit.
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
        return true
    }

    /// Bumps the revision and tells hosts to re-read the layout. Call after any
    /// change to the item set. (The tray *label* is an SNI property, not a menu
    /// property — changing it does not need this.)
    public func layoutChanged() {
        self.revision &+= 1
        guard self.registrationID != 0,
              let payload = TrayMenuLayout.parseVariant(text: "(\(self.revision), 0)", type: "(ui)")
        else {
            return
        }
        var error: UnsafeMutablePointer<GError>?
        g_dbus_connection_emit_signal(
            self.connection,
            nil,
            self.objectPath,
            Self.interfaceName,
            "LayoutUpdated",
            payload,
            &error)
        // emit_signal sinks a floating ref; ours is a full one from g_variant_parse.
        g_variant_unref(payload)
        if error != nil { self.logError("g_dbus_connection_emit_signal", error) }
    }

    private func logError(_ context: String, _ error: UnsafeMutablePointer<GError>?) {
        let message = error.map { String(cString: $0.pointee.message) } ?? "unknown error"
        FileHandle.standardError.write(Data("codexbar: \(context) failed: \(message)\n".utf8))
        if let error { g_error_free(error) }
    }

    // MARK: - Reading GVariant arguments

    private static func int32Child(_ parameters: OpaquePointer?, _ index: Int) -> Int32 {
        guard let parameters, let child = g_variant_get_child_value(parameters, gsize(index)) else {
            return 0
        }
        defer { g_variant_unref(child) }
        return g_variant_get_int32(child)
    }

    private static func stringChild(_ parameters: OpaquePointer?, _ index: Int) -> String {
        guard let parameters, let child = g_variant_get_child_value(parameters, gsize(index)) else {
            return ""
        }
        defer { g_variant_unref(child) }
        guard let raw = g_variant_get_string(child, nil) else { return "" }
        return String(cString: raw)
    }

    private static func stringArrayChild(_ parameters: OpaquePointer?, _ index: Int) -> [String] {
        guard let parameters, let array = g_variant_get_child_value(parameters, gsize(index)) else {
            return []
        }
        defer { g_variant_unref(array) }
        var result: [String] = []
        for offset in 0..<g_variant_n_children(array) {
            guard let element = g_variant_get_child_value(array, offset) else { continue }
            if let raw = g_variant_get_string(element, nil) { result.append(String(cString: raw)) }
            g_variant_unref(element)
        }
        return result
    }

    private static func int32ArrayChild(_ parameters: OpaquePointer?, _ index: Int) -> [Int32] {
        guard let parameters, let array = g_variant_get_child_value(parameters, gsize(index)) else {
            return []
        }
        defer { g_variant_unref(array) }
        var result: [Int32] = []
        for offset in 0..<g_variant_n_children(array) {
            guard let element = g_variant_get_child_value(array, offset) else { continue }
            result.append(g_variant_get_int32(element))
            g_variant_unref(element)
        }
        return result
    }

    // MARK: - Vtable

    private static let methodCallThunk: GDBusInterfaceMethodCallFunc = {
        _, _, _, _, methodName, parameters, invocation, userData in
        guard let userData, let methodName, let invocation else { return }
        let server = Unmanaged<TrayMenuServer>.fromOpaque(userData).takeUnretainedValue()
        server.handle(method: String(cString: methodName), parameters: parameters, invocation: invocation)
    }

    private func handle(method: String, parameters: OpaquePointer?, invocation: OpaquePointer) {
        switch method {
        case "GetLayout":
            let names = Self.stringArrayChild(parameters, 2)
            let text = TrayMenuLayout.layoutText(
                revision: self.revision,
                items: self.items,
                propertyNames: names)
            self.reply(invocation, text: text, type: "(u(ia{sv}av))", method: method)

        case "GetGroupProperties":
            let ids = Self.int32ArrayChild(parameters, 0)
            let names = Self.stringArrayChild(parameters, 1)
            let text = TrayMenuLayout.groupPropertiesText(
                ids: ids,
                items: self.items,
                propertyNames: names)
            self.reply(invocation, text: text, type: "(a(ia{sv}))", method: method)

        case "GetProperty":
            let id = Self.int32Child(parameters, 0)
            let name = Self.stringChild(parameters, 1)
            guard let text = TrayMenuLayout.propertyText(id: id, name: name, items: self.items) else {
                g_dbus_method_invocation_return_dbus_error(
                    invocation,
                    "com.canonical.dbusmenu.Error.UnknownProperty",
                    "No property \(name) on item \(id)")
                return
            }
            self.reply(invocation, text: text, type: "(v)", method: method)

        case "Event":
            let id = Self.int32Child(parameters, 0)
            let eventID = Self.stringChild(parameters, 1)
            if eventID == "clicked", let action = TrayMenuItem.actionName(forID: id, in: self.items) {
                self.activate(action)
            }
            g_dbus_method_invocation_return_value(invocation, nil)

        case "AboutToShow":
            // The menu is rebuilt from a static item list, so it is never stale.
            self.reply(invocation, text: "(false,)", type: "(b)", method: method)

        default:
            g_dbus_method_invocation_return_dbus_error(
                invocation,
                "org.freedesktop.DBus.Error.UnknownMethod",
                "Unknown dbusmenu method \(method)")
        }
    }

    private func reply(_ invocation: OpaquePointer, text: String, type: String, method: String) {
        guard let variant = TrayMenuLayout.parseVariant(text: text, type: type) else {
            g_dbus_method_invocation_return_dbus_error(
                invocation,
                "org.freedesktop.DBus.Error.Failed",
                "Could not serialize the \(method) reply")
            return
        }
        // return_value consumes the reference.
        g_dbus_method_invocation_return_value(invocation, variant)
    }

    private static let getPropertyThunk: GDBusInterfaceGetPropertyFunc = {
        _, _, _, _, propertyName, _, _ in
        guard let propertyName else { return nil }
        switch String(cString: propertyName) {
        case "Version":
            return g_variant_new_uint32(3)
        case "TextDirection":
            return g_variant_new_string("ltr")
        case "Status":
            return g_variant_new_string("normal")
        case "IconThemePath":
            return TrayMenuLayout.parseVariant(text: "@as []", type: "as")
        default:
            return nil
        }
    }
}
