import CAdwaita
import Foundation
import Testing
@testable import CodexBarLinuxKit

// `GSimpleAction` is a GObject that needs no display, so the wrapper is testable
// headlessly. Both `GSimpleAction *` and `GAction *` are opaque C structs, which
// the Clang importer flattens to the same `OpaquePointer` — hence no casts here.
@Test func `a connected handler runs when the signal fires`() {
    final class Counter: @unchecked Sendable { var value = 0 }
    let counter = Counter()

    let action = g_simple_action_new("test", nil)!
    defer { g_object_unref(UnsafeMutableRawPointer(action)) }

    Signal.connect(action, "activate") { counter.value += 1 }
    g_action_activate(action, nil)

    #expect(counter.value == 1)
}

// The connection is swapped precisely so one thunk serves every arity. `activate`
// on a `GSimpleAction` carries a `GVariant` and reaches the handler with three
// arguments; `activate` on a `GApplication` carries nothing and arrives with two.
// Unswapped, the user data sits last and only one of these two could ever work.
@Test func `one wrapper serves signals that carry a parameter and signals that do not`() {
    final class Counter: @unchecked Sendable { var value = 0 }
    let counter = Counter()

    // `GCancellable::cancelled` carries no parameter and needs neither a display
    // nor a bus to fire, which makes it the two-argument half of the comparison.
    let cancellable = g_cancellable_new()!
    defer { g_object_unref(UnsafeMutableRawPointer(cancellable)) }

    Signal.connect(OpaquePointer(cancellable), "cancelled") { counter.value += 1 }
    g_cancellable_cancel(cancellable)

    #expect(counter.value == 1)
}

@Test func `a disconnected handler stops running when the object dies`() {
    final class Counter: @unchecked Sendable { var value = 0 }
    let counter = Counter()

    let action = g_simple_action_new("test", nil)!
    Signal.connect(action, "activate") { counter.value += 1 }
    g_action_activate(action, nil)
    g_object_unref(UnsafeMutableRawPointer(action))

    // The box is released by the destroy notify, not leaked into the next emission.
    #expect(counter.value == 1)
}
