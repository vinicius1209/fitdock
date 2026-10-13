import Foundation

enum Format {
    private static let locale = Locale(identifier: "pt_BR")

    static func integer(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    static func kcal(_ value: Double) -> String {
        "\(Int(value.rounded()).formatted(.number.locale(locale))) kcal"
    }

    static func distance(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int(meters.rounded())) m" }
        return "\((meters / 1000).formatted(.number.precision(.fractionLength(1)).locale(locale))) km"
    }

    /// Versão curta para caber no ícone do Dock: 12.345 vira "12,3 mil".
    static func compactSteps(_ value: Int) -> String {
        if value < 10_000 { return integer(value) }
        let thousands = Double(value) / 1000
        return "\(thousands.formatted(.number.precision(.fractionLength(1)).locale(locale))) mil"
    }

    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
    }

    static func relative(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return "agora" }
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: now)
    }
}
