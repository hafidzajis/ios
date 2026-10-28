import Foundation
import SwiftData

/// Cached BNM USD->MYR rate for one day ("yyyy-MM-dd" key). De-duplicated by `dayKey` in code.
@Model
final class FXRate {
    var dayKey: String = ""
    var usdToMYR: Decimal = 0
    var fetchedAt: Date = Date()
    var isManual: Bool = false

    init(dayKey: String, usdToMYR: Decimal, fetchedAt: Date = Date(), isManual: Bool = false) {
        self.dayKey = dayKey
        self.usdToMYR = usdToMYR
        self.fetchedAt = fetchedAt
        self.isManual = isManual
    }
}
