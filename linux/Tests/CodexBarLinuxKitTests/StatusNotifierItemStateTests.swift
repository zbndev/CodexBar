import Foundation
import Testing

@testable import CodexBarLinuxKit

private func sampleState() -> StatusNotifierItemState {
    StatusNotifierItemState(
        id: "codexbar",
        title: "CodexBar",
        iconName: "codexbar",
        menuPath: "/org/ayatana/appindicator/codexbar")
}

@Test func `every declared property has a value of its declared type`() throws {
    let state = sampleState()
    for name in StatusNotifierItemState.propertyNames {
        // A nil here would make a host drop the item, so require rather than
        // skip: an unanswered declared property is the bug being hunted.
        let text = try #require(state.propertyText(for: name), "\(name) has no value")
        let type = try #require(state.propertyType(for: name), "\(name) has no type")
        #expect(
            TrayMenuLayout.parses(text, as: type),
            "\(name) produced \(text), which is not a valid \(type)")
    }
}

@Test func `an undeclared property has no value`() {
    #expect(sampleState().propertyText(for: "ItemIsMenu") == nil)
}

@Test func `the menu property is an object path, not a string`() {
    let state = sampleState()
    #expect(state.propertyType(for: "Menu") == "o")
    #expect(state.propertyText(for: "Menu") == "objectpath '/org/ayatana/appindicator/codexbar'")
}

@Test func `a label with a quote survives escaping`() throws {
    var state = sampleState()
    state.label = "it's 92%"
    let text = try #require(state.propertyText(for: "XAyatanaLabel"))
    #expect(text == "'it\\'s 92%'")
    #expect(TrayMenuLayout.parses(text, as: "s"))
}

@Test func `the tooltip carries the title so hosts without a label still name the app`() throws {
    let text = try #require(sampleState().propertyText(for: "ToolTip"))
    #expect(text.contains("'CodexBar'"))
    #expect(TrayMenuLayout.parses(text, as: "(sa(iiay)ss)"))
}
