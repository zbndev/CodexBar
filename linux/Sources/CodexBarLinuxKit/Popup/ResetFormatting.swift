import Foundation

/// The popup's reset wording, ported from `app.js`'s `formatReset`,
/// `resetCountdown` and `absoluteReset`.
///
/// `now` is a parameter rather than `Date()` because that is the only reason
/// the web version was never unit-tested: every branch below turns on how far
/// away the reset is, and a function that reads the wall clock can only be
/// tested by waiting.
public enum ResetFormatting {
    /// Mirrors `UsageFormatter.resetLine`: same precedence, same wording, same
    /// localisation keys.
    ///
    /// The old order let a provider's `resetDescription` win over the countdown
    /// even when a reset date was known, which had two consequences. The
    /// reset-time preference was silently ignored for every provider that ships
    /// a description, and the popup printed the description raw — for Claude
    /// that is a fragment scraped off the `claude` CLI
    /// ("Resets10pm(Europe/Moscow)"), sitting next to providers that showed a
    /// tidy line. Upstream normalises exactly this; the web layer simply never
    /// did.
    ///
    /// `strings` is the snapshot's localisation catalog. It defaults to empty,
    /// where every key resolves to its own English text — which is what the
    /// keys literally are upstream.
    public static func line(
        for window: ProviderWindowView,
        now: Date,
        showAbsolute: Bool,
        strings: [String: String] = [:],
        calendar: Calendar = .current) -> String
    {
        if let date = window.resetsAt {
            if showAbsolute {
                let absolute = self.absolute(
                    date, now: now, strings: strings, calendar: calendar)
                return self.localized("Resets %@", absolute, strings)
            }
            guard let countdown = self.countdown(to: date, now: now) else {
                return self.localized("Resets now", nil, strings)
            }
            return self.localized("Resets in %@", countdown, strings)
        }

        // No usable date: fall back to whatever the provider said, minus the
        // verb it may already carry, so the line reads the same either way. The
        // separator is optional because a scrape can arrive unspaced
        // ("Resets10pm(…)") — the same shape `ClaudeStatusProbe.cleanResetLine`
        // strips upstream.
        let described = (window.resetDescription ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if described.isEmpty { return "" }
        let body = self.strippingResetVerb(described)
        if body.isEmpty { return self.localized("Resets now", nil, strings) }
        if let counted = self.remainderAfterIn(body) {
            return self.localized("Resets in %@", counted, strings)
        }
        return self.localized("Resets %@", body, strings)
    }

    /// The remaining time, without the leading verb. Nil means "now" — under a
    /// second left, where a countdown would read as `0m`.
    public static func countdown(to date: Date, now: Date) -> String? {
        let seconds = max(0, date.timeIntervalSince(now))
        if seconds < 1 { return nil }
        let totalMinutes = max(1, Int(ceil(seconds / 60)))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60
        if days > 0 {
            if hours > 0 { return "\(days)d \(hours)h" }
            if minutes > 0 { return "\(days)d \(minutes)m" }
            return "\(days)d"
        }
        if hours > 0 {
            if minutes > 0 { return "\(hours)h \(minutes)m" }
            return "\(hours)h"
        }
        return "\(totalMinutes)m"
    }

    /// Today drops the date, tomorrow says so, anything further carries both.
    public static func absolute(
        _ date: Date,
        now: Date,
        strings: [String: String] = [:],
        calendar: Calendar = .current) -> String
    {
        let time = self.timeFormatter(calendar).string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow)
        {
            return self.localized(
                "reset_tomorrow_format", fallback: "tomorrow, %@", time, strings)
        }
        return self.dateAndTimeFormatter(calendar).string(from: date)
    }

    // MARK: - Wording

    /// `i18n.js`'s `t()`, narrowed to the four keys this file uses: look the key
    /// up and fill the single `%@`. None of the four carries a positional or
    /// numeric specifier, so the general substituter the web layer needed is not
    /// required here.
    private static func localized(
        _ key: String,
        fallback: String,
        _ value: String?,
        _ strings: [String: String]) -> String
    {
        let template = strings[key] ?? fallback
        guard let value else { return template }
        guard let placeholder = template.range(of: "%@") else { return template }
        return template.replacingCharacters(in: placeholder, with: value)
    }

    /// Three of the four keys are their own English text upstream, which is
    /// what makes an empty catalog render English rather than key names.
    private static func localized(
        _ key: String,
        _ value: String?,
        _ strings: [String: String]) -> String
    {
        self.localized(key, fallback: key, value, strings)
    }

    // MARK: - Description parsing

    /// Strips a leading `reset`/`resets`, an optional colon, and the spaces
    /// around it. A prefix scan rather than a regex: the shape is fixed, and
    /// the scan can stop at a word boundary, which is what keeps "Resetting
    /// soon" intact.
    private static func strippingResetVerb(_ text: String) -> String {
        var rest = Substring(text)
        guard rest.lowercased().hasPrefix("reset") else { return text }
        rest = rest.dropFirst(5)
        if let next = rest.first, next == "s" || next == "S" { rest = rest.dropFirst() }
        // A letter here means the word only began with the verb — "Resetting",
        // not "Resets" plus a body — so nothing is stripped.
        if let next = rest.first, next.isLetter { return text }
        rest = rest.drop(while: \.isWhitespace)
        if rest.first == ":" { rest = rest.dropFirst() }
        rest = rest.drop(while: \.isWhitespace)
        return String(rest)
    }

    /// The body of an "in …" description, so a described countdown lands on the
    /// same "Resets in %@" key a computed one does.
    private static func remainderAfterIn(_ body: String) -> String? {
        guard body.lowercased().hasPrefix("in") else { return nil }
        let rest = body.dropFirst(2)
        guard let next = rest.first, next.isWhitespace else { return nil }
        let remainder = rest.drop(while: \.isWhitespace)
        return remainder.isEmpty ? nil : String(remainder)
    }

    // MARK: - Formatters

    private static func timeFormatter(_ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? Locale.current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    private static func dateAndTimeFormatter(_ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? Locale.current
        // Template rather than styles: the JS asked for a short month, a day
        // and a time with no year, and `.short`/`.short` would add the year
        // back in most locales.
        formatter.setLocalizedDateFormatFromTemplate("MMMdjmm")
        return formatter
    }
}
