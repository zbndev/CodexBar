import Foundation
import Testing

@testable import CodexBarLinuxKit

@Test func `strings parser handles comments escapes and substitutions`() throws {
    let source = #"""
    /* heading */
    "simple" = "Value";
    "quote" = "A \"quoted\" value";
    // substitutions stay verbatim
    "days" = "%d days for %@";
    "percent" = "100%%";
    """#
    let parsed = try LocalizationCatalog.parseStrings(source)
    #expect(parsed["simple"] == "Value")
    #expect(parsed["quote"] == #"A "quoted" value"#)
    #expect(parsed["days"] == "%d days for %@")
    #expect(parsed["percent"] == "100%%")
}

@Test func `english catalog contains the upstream keys and linux additions`() {
    let payload = LocalizationCatalog.load(locale: "en")
    #expect(payload.strings.count >= 1307)
    #expect(payload.strings["tab_general"] != nil)
    #expect(payload.strings["linux.settings.title"] == "Settings")
}

@Test func `selected locale overlays english and missing keys fall back`() {
    let english = LocalizationCatalog.load(locale: "en")
    let german = LocalizationCatalog.load(locale: "de")
    #expect(german.locale == "de")
    #expect(german.strings["tab_general"] != nil)
    #expect(german.strings["General"] == german.strings["tab_general"])
    for key in LinuxStrings.english.keys {
        #expect(german.strings[key] == english.strings[key])
    }
}

@Test func `unsupported locale falls back to english`() {
    #expect(LocalizationCatalog.load(locale: "xx-NOPE").locale == "en")
}

@Test func `all 23 locale catalogs load`() {
    #expect(LocalizationCatalog.supportedLocales.count == 23)
    for locale in LocalizationCatalog.supportedLocales {
        let payload = LocalizationCatalog.load(locale: locale)
        #expect(payload.locale == locale)
        #expect(!payload.strings.isEmpty)
    }
}

@Test func `english stringsdict exposes one and other plural forms`() {
    let payload = LocalizationCatalog.load(locale: "en")
    let entry = payload.plurals.values.first
    #expect(entry?.format.contains("%#@") == true)
    #expect(entry?.variables.values.contains { $0["one"] != nil } == true)
    #expect(entry?.variables.values.contains { $0["other"] != nil } == true)
}

@Test func `unicode escapes decode in legacy strings`() throws {
    let parsed = try LocalizationCatalog.parseStrings(#""quote" = "\U201cHello\U201d";"#)
    #expect(parsed["quote"] == "“Hello”")
}

@Test func `stringsdict keeps independent named plural variables`() {
    let payload = LocalizationCatalog.load(locale: "en")
    #expect(payload.plurals.values.contains { $0.variables.count >= 2 })
}

@Test func `localization payload round-trips through JSON`() throws {
    let original = LocalizationCatalog.load(locale: "pt-BR")
    let decoded = try JSONDecoder().decode(
        LocalizationPayload.self, from: JSONEncoder().encode(original))
    #expect(decoded == original)
}
