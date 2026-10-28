import SwiftUI

extension Color {
    static func pnl(_ value: Decimal) -> Color {
        if value > 0 { return .green }
        if value < 0 { return .red }
        return .secondary
    }
}

/// Colored, signed money in the user's display currency.
struct PnLText: View {
    @Environment(AppSettings.self) private var settings
    let value: Decimal
    var signed = true

    var body: some View {
        Text(signed ? settings.signedMoney(value) : settings.money(value))
            .foregroundStyle(Color.pnl(value))
            .monospacedDigit()
    }
}
