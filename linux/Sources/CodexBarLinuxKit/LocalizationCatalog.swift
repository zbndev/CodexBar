import Foundation

public struct PluralEntry: Codable, Equatable, Sendable {
    public var format: String
    public var variables: [String: [String: String]]
}

public struct LocalizationPayload: Codable, Equatable, Sendable {
    public var locale: String
    public var strings: [String: String]
    public var plurals: [String: PluralEntry]
}

/// Loads the upstream `.strings` / `.stringsdict` catalogs for the web UI.
///
/// Reads through ``LinuxResourceRoot``, so an installed package uses its own
/// copy.
public enum LocalizationCatalog {
    public static let supportedLocales = [
        "ar", "ca", "de", "en", "es", "fa", "fr", "gl", "id", "it", "ja", "ko",
        "nl", "pl", "pt-BR", "ru", "sv", "th", "tr", "uk", "vi", "zh-Hans", "zh-Hant",
    ]

    public static var resourcesDirectory: URL {
        LinuxResourceRoot.providerResources
    }

    public static func load(locale requested: String?) -> LocalizationPayload {
        let locale = self.resolveLocale(requested)
        let english = self.loadStrings(locale: "en").merging(LinuxStrings.english) { _, linux in linux }
        let selected = locale == "en" ? [:] : self.loadStrings(locale: locale)
        var strings = english.merging(selected) { _, localized in localized }
        // PaneRow currently carries display labels, while the upstream
        // catalogs mostly use semantic keys. Add an English-value alias so
        // `t("General")` resolves through `tab_general` in every locale.
        for (key, englishValue) in english {
            strings[englishValue] = selected[key] ?? englishValue
        }

        let englishPlurals = self.loadPlurals(locale: "en")
        let selectedPlurals = locale == "en" ? [:] : self.loadPlurals(locale: locale)
        return LocalizationPayload(
            locale: locale,
            strings: strings,
            plurals: englishPlurals.merging(selectedPlurals) { _, localized in localized })
    }

    private static func resolveLocale(_ requested: String?) -> String {
        let raw = (requested ?? Locale.current.identifier).replacingOccurrences(of: "_", with: "-")
        if self.supportedLocales.contains(raw) { return raw }
        let language = raw.split(separator: "-").first.map(String.init) ?? "en"
        return self.supportedLocales.contains(language) ? language : "en"
    }

    private static func loadStrings(locale: String) -> [String: String] {
        let url = self.resourcesDirectory
            .appendingPathComponent("\(locale).lproj/Localizable.strings")
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return (try? self.parseStrings(source)) ?? [:]
    }

    private static func loadPlurals(locale: String) -> [String: PluralEntry] {
        let url = self.resourcesDirectory
            .appendingPathComponent("\(locale).lproj/Localizable.stringsdict")
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? self.parseStringsDict(data)) ?? [:]
    }

    /// Parser for legacy `.strings`: comments, quoted strings, C escapes,
    /// equals and semicolon separators. It deliberately keeps `%@`, `%d`
    /// and `%%` untouched — substitution happens in JS.
    public static func parseStrings(_ source: String) throws -> [String: String] {
        var scanner = StringsScanner(source)
        var result: [String: String] = [:]
        while scanner.skipTrivia() {
            let key = try scanner.quotedString()
            try scanner.expect("=")
            let value = try scanner.quotedString()
            try scanner.expect(";")
            result[key] = value
        }
        return result
    }

    /// Extracts plural forms from a `.stringsdict` XML plist while
    /// preserving the localized format string and every named variable.
    /// The English catalog contains a two-variable entry, so flattening by
    /// category would lose information.
    public static func parseStringsDict(_ data: Data) throws -> [String: PluralEntry] {
        guard let root = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any]
        else { return [:] }
        var result: [String: PluralEntry] = [:]
        for (key, rawEntry) in root {
            guard let entry = rawEntry as? [String: Any] else { continue }
            guard let format = entry["NSStringLocalizedFormatKey"] as? String else { continue }
            var variables: [String: [String: String]] = [:]
            for (name, value) in entry where name != "NSStringLocalizedFormatKey" {
                guard let variable = value as? [String: Any],
                      variable["NSStringFormatSpecTypeKey"] as? String == "NSStringPluralRuleType"
                else { continue }
                var forms: [String: String] = [:]
                for category in ["zero", "one", "two", "few", "many", "other"] {
                    if let text = variable[category] as? String { forms[category] = text }
                }
                if !forms.isEmpty { variables[name] = forms }
            }
            if !variables.isEmpty {
                result[key] = PluralEntry(format: format, variables: variables)
            }
        }
        return result
    }
}

private struct StringsScanner {
    enum ScanError: Error { case expected(String, Int); case unterminatedString(Int) }

    private let scalars: [Unicode.Scalar]
    private var index = 0

    init(_ source: String) { self.scalars = Array(source.unicodeScalars) }

    mutating func skipTrivia() -> Bool {
        while self.index < self.scalars.count {
            if CharacterSet.whitespacesAndNewlines.contains(self.scalars[self.index]) {
                self.index += 1
            } else if self.peek("//") {
                while self.index < self.scalars.count, self.scalars[self.index] != "\n" { self.index += 1 }
            } else if self.peek("/*") {
                self.index += 2
                while self.index + 1 < self.scalars.count, !self.peek("*/") { self.index += 1 }
                if self.index + 1 < self.scalars.count { self.index += 2 }
            } else { break }
        }
        return self.index < self.scalars.count
    }

    mutating func expect(_ token: Unicode.Scalar) throws {
        _ = self.skipTrivia()
        guard self.index < self.scalars.count, self.scalars[self.index] == token else {
            throw ScanError.expected(String(token), self.index)
        }
        self.index += 1
    }

    mutating func quotedString() throws -> String {
        try self.expect("\"")
        var result = ""
        while self.index < self.scalars.count {
            let scalar = self.scalars[self.index]
            self.index += 1
            if scalar == "\"" { return result }
            if scalar == "\\" {
                guard self.index < self.scalars.count else { break }
                let escaped = self.scalars[self.index]
                self.index += 1
                switch escaped {
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "U", "u":
                    guard self.index + 4 <= self.scalars.count else {
                        throw ScanError.unterminatedString(self.index)
                    }
                    let hex = self.scalars[self.index..<(self.index + 4)]
                        .map(String.init)
                        .joined()
                    guard let value = UInt32(hex, radix: 16),
                          let scalar = Unicode.Scalar(value)
                    else { throw ScanError.expected("four hex digits", self.index) }
                    result.unicodeScalars.append(scalar)
                    self.index += 4
                default: result.unicodeScalars.append(escaped)
                }
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        throw ScanError.unterminatedString(self.index)
    }

    private func peek(_ text: String) -> Bool {
        let probe = Array(text.unicodeScalars)
        guard self.index + probe.count <= self.scalars.count else { return false }
        return Array(self.scalars[self.index..<(self.index + probe.count)]) == probe
    }
}
