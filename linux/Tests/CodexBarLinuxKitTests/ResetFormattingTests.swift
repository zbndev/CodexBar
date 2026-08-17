import Foundation
import Testing

@testable import CodexBarLinuxKit

private func window(
    resetsAt: Date? = nil,
    description: String? = nil) -> ProviderWindowView
{
    ProviderWindowView(
        id: "w",
        title: "Weekly",
        usedPercent: 40,
        resetsAt: resetsAt,
        resetDescription: description)
}

@Test func `a countdown rounds minutes up and drops empty units`() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(ResetFormatting.countdown(to: now.addingTimeInterval(90), now: now) == "2m")
    #expect(ResetFormatting.countdown(to: now.addingTimeInterval(3600), now: now) == "1h")
    #expect(ResetFormatting.countdown(to: now.addingTimeInterval(3900), now: now) == "1h 5m")
    #expect(ResetFormatting.countdown(to: now.addingTimeInterval(86_400), now: now) == "1d")
    #expect(ResetFormatting.countdown(to: now.addingTimeInterval(90_000), now: now) == "1d 1h")
}

@Test func `a day and some minutes skips the empty hour rather than printing it`() {
    // `1d 5m`, never `1d 0h 5m`: the JS ladder falls through to minutes only
    // when the hour slot is empty, and the port has to fall the same way.
    let now = Date(timeIntervalSince1970: 0)
    #expect(ResetFormatting.countdown(to: now.addingTimeInterval(86_700), now: now) == "1d 5m")
}

@Test func `under a second left reads as now rather than zero minutes`() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(ResetFormatting.countdown(to: now.addingTimeInterval(0.5), now: now) == nil)
    #expect(ResetFormatting.countdown(to: now.addingTimeInterval(-100), now: now) == nil)
}

@Test func `a known reset date beats the provider's own description`() {
    let now = Date(timeIntervalSince1970: 0)
    let line = ResetFormatting.line(
        for: window(resetsAt: now.addingTimeInterval(3600), description: "Resets10pm(Europe/Moscow)"),
        now: now,
        showAbsolute: false)
    #expect(line == "Resets in 1h")
}

@Test func `a reset that has already passed reads as now`() {
    let now = Date(timeIntervalSince1970: 10_000)
    let line = ResetFormatting.line(
        for: window(resetsAt: now.addingTimeInterval(-60)), now: now, showAbsolute: false)
    #expect(line == "Resets now")
}

@Test func `a description loses its leading verb whether or not it is spaced`() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(ResetFormatting.line(for: window(description: "Resets10pm"), now: now, showAbsolute: false)
        == "Resets 10pm")
    #expect(ResetFormatting.line(for: window(description: "resets: in 3 hours"), now: now, showAbsolute: false)
        == "Resets in 3 hours")
    #expect(ResetFormatting.line(for: window(), now: now, showAbsolute: false).isEmpty)
}

@Test func `a bare verb with nothing after it reads as now`() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(ResetFormatting.line(for: window(description: "Reset:"), now: now, showAbsolute: false)
        == "Resets now")
    #expect(ResetFormatting.line(for: window(description: "   "), now: now, showAbsolute: false).isEmpty)
}

@Test func `a description that only starts like the verb keeps its whole text`() {
    // "Resetting" is not the verb plus a body, so nothing is stripped — the
    // prefix scan has to stop at the word, not at the letters.
    let now = Date(timeIntervalSince1970: 0)
    #expect(ResetFormatting.line(for: window(description: "Resetting soon"), now: now, showAbsolute: false)
        == "Resets Resetting soon")
    // Same for a body that merely begins with the letters of "in".
    #expect(ResetFormatting.line(for: window(description: "resets index rebuild"), now: now, showAbsolute: false)
        == "Resets index rebuild")
}

@Test func `the absolute form drops the date for today and names tomorrow`() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    let now = Date(timeIntervalSince1970: 1_755_432_000) // 2025-08-17 12:00 UTC

    let today = ResetFormatting.absolute(now.addingTimeInterval(3600), now: now, calendar: calendar)
    #expect(!today.contains("tomorrow"))
    #expect(today.contains("1"))

    let tomorrow = ResetFormatting.absolute(now.addingTimeInterval(86_400), now: now, calendar: calendar)
    #expect(tomorrow.hasPrefix("tomorrow, "))

    // Anything further out carries the day as well, so it can never be read as
    // today's clock time.
    let later = ResetFormatting.absolute(now.addingTimeInterval(5 * 86_400), now: now, calendar: calendar)
    #expect(later != today)
    #expect(!later.hasPrefix("tomorrow"))
}

@Test func `showing absolute times replaces the countdown entirely`() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    let now = Date(timeIntervalSince1970: 1_755_432_000)
    let line = ResetFormatting.line(
        for: window(resetsAt: now.addingTimeInterval(3600)),
        now: now,
        showAbsolute: true,
        calendar: calendar)
    #expect(line.hasPrefix("Resets "))
    #expect(!line.hasPrefix("Resets in "))
}

@Test func `a supplied catalog localizes the wording the way the web layer did`() {
    // The three keys used here all exist upstream, so the line stays translated
    // in the 23 shipped locales instead of hardening into English.
    let now = Date(timeIntervalSince1970: 0)
    let strings = [
        "Resets in %@": "Сброс через %@",
        "Resets now": "Сброс сейчас",
        "Resets %@": "Сброс %@",
    ]
    #expect(ResetFormatting.line(
        for: window(resetsAt: now.addingTimeInterval(3600)),
        now: now,
        showAbsolute: false,
        strings: strings) == "Сброс через 1h")
    #expect(ResetFormatting.line(
        for: window(resetsAt: now),
        now: now,
        showAbsolute: false,
        strings: strings) == "Сброс сейчас")
    #expect(ResetFormatting.line(
        for: window(description: "Resets10pm"),
        now: now,
        showAbsolute: false,
        strings: strings) == "Сброс 10pm")
}

@Test func `an untranslated key falls back to its own English text`() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(ResetFormatting.line(
        for: window(resetsAt: now.addingTimeInterval(3600)),
        now: now,
        showAbsolute: false,
        strings: ["Something Else": "…"]) == "Resets in 1h")
}
