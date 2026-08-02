import Foundation
import Testing

@testable import CodexBarLinuxKit

private let sample: [TrayMenuItem] = [
    TrayMenuItem(id: 1, label: "Open CodexBar", actionName: "show"),
    TrayMenuItem(id: 2, label: "Refresh", actionName: "refresh"),
    TrayMenuItem.separator(id: 3),
    TrayMenuItem(id: 4, label: "Quit", actionName: "quit"),
]

@Test func `quoting escapes backslashes before quotes`() {
    #expect(TrayMenuLayout.quote("plain") == "'plain'")
    #expect(TrayMenuLayout.quote("it's") == #"'it\'s'"#)
    #expect(TrayMenuLayout.quote(#"back\slash"#) == #"'back\\slash'"#)
    // A backslash immediately before a quote must not consume that quote's escape.
    #expect(TrayMenuLayout.quote(#"a\'b"#) == #"'a\\\'b'"#)
}

@Test func `layout text nests every item under the root and parses as a variant`() {
    let text = TrayMenuLayout.layoutText(revision: 7, items: sample, propertyNames: [])
    #expect(text.hasPrefix("(7, (0, {'children-display': <'submenu'>}, ["))
    #expect(text.contains("<(1, {'label': <'Open CodexBar'>, 'enabled': <true>, 'visible': <true>, 'type': <'standard'>}, @av [])>"))
    #expect(text.contains("<(3, {'enabled': <true>, 'visible': <true>, 'type': <'separator'>}, @av [])>"))
    #expect(TrayMenuLayout.parses(text, as: "(u(ia{sv}av))"))
}

@Test func `layout honors a non-empty property filter`() {
    let text = TrayMenuLayout.layoutText(revision: 1, items: sample, propertyNames: ["label"])
    #expect(text.contains("<(1, {'label': <'Open CodexBar'>}, @av [])>"))
    #expect(!text.contains("'enabled'"))
    #expect(TrayMenuLayout.parses(text, as: "(u(ia{sv}av))"))
}

@Test func `group properties returns only the requested ids`() {
    let text = TrayMenuLayout.groupPropertiesText(ids: [2, 4], items: sample, propertyNames: [])
    #expect(text.contains("(2, {'label': <'Refresh'>"))
    #expect(text.contains("(4, {'label': <'Quit'>"))
    #expect(!text.contains("'Open CodexBar'"))
    #expect(TrayMenuLayout.parses(text, as: "(a(ia{sv}))"))
}

@Test func `group properties on an empty id list returns every item`() {
    let text = TrayMenuLayout.groupPropertiesText(ids: [], items: sample, propertyNames: [])
    #expect(text.contains("'Open CodexBar'"))
    #expect(text.contains("'Quit'"))
    #expect(TrayMenuLayout.parses(text, as: "(a(ia{sv}))"))
}

@Test func `single property lookup finds and misses correctly`() {
    #expect(TrayMenuLayout.propertyText(id: 2, name: "label", items: sample) == "(<'Refresh'>,)")
    #expect(TrayMenuLayout.propertyText(id: 3, name: "label", items: sample) == nil)
    #expect(TrayMenuLayout.propertyText(id: 99, name: "label", items: sample) == nil)
}

@Test func `an empty menu still produces a parseable root`() {
    let text = TrayMenuLayout.layoutText(revision: 1, items: [], propertyNames: [])
    #expect(text == "(1, (0, {'children-display': <'submenu'>}, @av []))")
    #expect(TrayMenuLayout.parses(text, as: "(u(ia{sv}av))"))
}

@Test func `a label needing escapes survives the round trip`() {
    let items = [TrayMenuItem(id: 1, label: #"Quit 'CodexBar\"#, actionName: "quit")]
    let text = TrayMenuLayout.layoutText(revision: 1, items: items, propertyNames: [])
    #expect(TrayMenuLayout.parses(text, as: "(u(ia{sv}av))"))
}

@Test func `action lookup maps ids back to action names`() {
    #expect(TrayMenuItem.actionName(forID: 4, in: sample) == "quit")
    #expect(TrayMenuItem.actionName(forID: 3, in: sample) == nil)
    #expect(TrayMenuItem.actionName(forID: 99, in: sample) == nil)
}

@Test func `the shipped tray menu has unique ids and an action for every visible item`() {
    let items = TrayIndicator.menuItems
    #expect(Set(items.map(\.id)).count == items.count)
    #expect(items.allSatisfy { $0.isSeparator || $0.actionName != nil })
    // Root is id 0 in dbusmenu; no item may collide with it.
    #expect(items.allSatisfy { $0.id != 0 })
}
