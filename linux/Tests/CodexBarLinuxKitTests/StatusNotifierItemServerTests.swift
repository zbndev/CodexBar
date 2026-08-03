import Foundation
import Testing

@testable import CodexBarLinuxKit

@Test func `the introspection XML declares every modelled property`() {
    let names = StatusNotifierItemServer.declaredPropertyNames()
    #expect(!names.isEmpty, "no properties were read out of the XML at all")
    for name in StatusNotifierItemState.propertyNames {
        #expect(names.contains(name), "\(name) is modelled but not declared in the XML")
    }
}

@Test func `the XML declares the signals the tray emits`() {
    let signals = StatusNotifierItemServer.declaredSignalNames()
    // emit_signal validates against the registered interface, so an
    // undeclared signal is a silent runtime failure rather than a build error.
    for name in ["NewIcon", "NewTitle", "NewStatus", "NewToolTip", "XAyatanaNewLabel"] {
        #expect(signals.contains(name), "\(name) is emitted but not declared")
    }
}

@Test func `the XML declares the methods hosts call`() {
    let methods = StatusNotifierItemServer.declaredMethodNames()
    for name in ["Activate", "SecondaryActivate", "XAyatanaSecondaryActivate", "Scroll"] {
        #expect(methods.contains(name), "\(name) is missing")
    }
}
