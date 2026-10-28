import SwiftUI
import SwiftData
import TradeLogCore

struct CalendarView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Trade.createdAt, order: .reverse) private var trades: [Trade]

    @State private var monthStart: Date = {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }()
    @State private var selectedDay: Date?

    private var calendar: Calendar { .current }

    private var activeTrades: [Trade] { trades.filter { !$0.isArchived } }

    private var dailyMap: [Date: DailyPnL] {
        let report = PerformanceAnalyzer.analyze(activeTrades.snapshots, calendar: calendar)
        var map: [Date: DailyPnL] = [:]
        for d in report.dailyPnL { map[calendar.startOfDay(for: d.day)] = d }
        return map
    }

    private var gridDays: [Date?] {
        let range = calendar.range(of: .day, in: .month, for: monthStart) ?? 1 ..< 31
        let offset = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: offset)
        for day in range {
            days.append(calendar.date(byAdding: .day, value: day - 1, to: monthStart))
        }
        return days
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    var body: some View {
        let map = dailyMap
        let monthDays = gridDays.compactMap { $0 }.compactMap { map[$0] }
        let monthTotal = monthDays.reduce(Decimal(0)) { $0 + $1.pnl }
        let maxAbs = monthDays.map { abs($0.pnl.doubleValue) }.max() ?? 0

        ScrollView {
            VStack(spacing: 16) {
                header(total: monthTotal, days: monthDays.count)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(weekdaySymbols, id: \.self) { s in
                        Text(s).font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                        if let day {
                            cell(day: day, entry: map[day], maxAbs: maxAbs)
                        } else {
                            Color.clear.frame(height: 52)
                        }
                    }
                }
                if let selectedDay { dayDetail(selectedDay) }
            }
            .padding(16)
        }
        .navigationTitle("Calendar")
        .tradeDestinations()
    }

    private func header(total: Decimal, days: Int) -> some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous month")
            Spacer()
            VStack {
                Text(monthStart.formatted(.dateTime.month(.wide).year())).font(.headline)
                HStack(spacing: 4) {
                    Text("Month total").foregroundStyle(.secondary)
                    PnLText(value: total)
                }
                .font(.subheadline)
            }
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next month")
        }
    }

    private func cell(day: Date, entry: DailyPnL?, maxAbs: Double) -> some View {
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let intensity = (entry != nil && maxAbs > 0) ? abs(entry!.pnl.doubleValue) / maxAbs : 0
        let color: Color = (entry?.pnl ?? 0) >= 0 ? .green : .red
        return Button {
            selectedDay = isSelected ? nil : day
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))").font(.caption2).foregroundStyle(.secondary)
                if let entry {
                    Text(compact(entry.pnl)).font(.caption2.weight(.semibold)).minimumScaleFactor(0.6).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(entry == nil ? Color.secondary.opacity(0.08) : color.opacity(0.15 + 0.6 * intensity),
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private func compact(_ value: Decimal) -> String {
        let v = settings.convert(value).doubleValue
        let sign = v > 0 ? "+" : (v < 0 ? "-" : "")
        let a = abs(v)
        if a >= 1000 { return sign + (a / 1000).formatted(.number.precision(.fractionLength(1))) + "k" }
        return sign + a.formatted(.number.precision(.fractionLength(0)))
    }

    private func dayDetail(_ day: Date) -> some View {
        let dayTrades = activeTrades.filter { calendar.isDate($0.sortDate, inSameDayAs: day) }
        return VStack(alignment: .leading, spacing: 8) {
            Text(day.formatted(date: .complete, time: .omitted)).font(.headline)
            if dayTrades.isEmpty {
                Text("No trades on this day.").foregroundStyle(.secondary)
            }
            ForEach(dayTrades) { trade in
                NavigationLink(value: trade) { TradeRow(trade: trade) }
                    .buttonStyle(.plain)
                Divider()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func shiftMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: monthStart) {
            monthStart = next
            selectedDay = nil
        }
    }
}
