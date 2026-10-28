import SwiftUI
import TradeLogCore

struct TradeRow: View {
    let trade: Trade

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(trade.symbol).font(.headline)
                    SideBadge(side: trade.side)
                    if trade.leverage > 1 {
                        Text("\(Fmt.plain(trade.leverage))x")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if trade.isOpen { OutcomeBadge(outcome: .open) }
                }
                Text(trade.sortDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if trade.isOpen && trade.cachedNetPnL == 0 {
                    Text("Open").foregroundStyle(.secondary)
                } else {
                    PnLText(value: trade.cachedNetPnL).font(.headline)
                }
                if let r = trade.cachedRMultiple {
                    Text(Fmt.r(r)).font(.caption).foregroundStyle(Color.pnl(r))
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
