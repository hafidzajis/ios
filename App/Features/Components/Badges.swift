import SwiftUI
import TradeLogCore

struct SideBadge: View {
    let side: TradeSide
    var body: some View {
        Text(side == .long ? "LONG" : "SHORT")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(side == .long ? Color.green : Color.red)
            .background((side == .long ? Color.green : Color.red).opacity(0.15), in: Capsule())
    }
}

struct OutcomeBadge: View {
    let outcome: TradeOutcome

    private var title: String {
        switch outcome {
        case .open: return "OPEN"
        case .win: return "WIN"
        case .loss: return "LOSS"
        case .breakeven: return "B/E"
        }
    }

    private var color: Color {
        switch outcome {
        case .open: return .blue
        case .win: return .green
        case .loss: return .red
        case .breakeven: return .gray
        }
    }

    var body: some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}
