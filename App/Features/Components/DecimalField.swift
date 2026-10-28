import SwiftUI

/// Locale-aware decimal text field.
struct DecimalField: View {
    let title: String
    @Binding var value: Decimal?
    @State private var text = ""

    init(_ title: String, value: Binding<Decimal?>) {
        self.title = title
        self._value = value
    }

    /// Non-optional variant: empty input becomes 0.
    init(_ title: String, amount: Binding<Decimal>) {
        self.title = title
        self._value = Binding<Decimal?>(
            get: { amount.wrappedValue },
            set: { amount.wrappedValue = $0 ?? 0 }
        )
    }

    var body: some View {
        TextField(title, text: $text)
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
            .multilineTextAlignment(.trailing)
            .onAppear { text = Self.format(value) }
            .onChange(of: text) { _, newText in
                let parsed = Self.parse(newText)
                if parsed != value { value = parsed }
            }
            .onChange(of: value) { _, newValue in
                if Self.parse(text) != newValue { text = Self.format(newValue) }
            }
    }

    static func parse(_ string: String) -> Decimal? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed, locale: Locale.current)
    }

    static func format(_ value: Decimal?) -> String {
        guard let value else { return "" }
        let f = NumberFormatter()
        f.locale = Locale.current
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.maximumFractionDigits = 8
        f.minimumFractionDigits = 0
        return f.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }
}
