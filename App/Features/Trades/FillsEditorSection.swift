import SwiftUI
import TradeLogCore

struct FillsEditorSection: View {
    @Binding var fills: [FillDraft]

    var body: some View {
        Section {
            ForEach($fills) { $fill in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Picker("Action", selection: $fill.action) {
                            Text("Open").tag(FillAction.open)
                            Text("Close").tag(FillAction.close)
                        }
                        .pickerStyle(.segmented)
                        Button(role: .destructive) {
                            let id = fill.id
                            fills.removeAll { $0.id == id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove fill")
                    }
                    DatePicker("Date", selection: $fill.date)
                    LabeledContent("Price") { DecimalField("0.00", value: $fill.price) }
                    LabeledContent("Quantity") { DecimalField("0", value: $fill.quantity) }
                    LabeledContent("Fee") { DecimalField("0.00", value: $fill.fee) }
                }
                .padding(.vertical, 4)
            }
            Button { addFill(.open) } label: { Label("Add open fill", systemImage: "plus.circle") }
            Button { addFill(.close) } label: { Label("Add close fill", systemImage: "minus.circle") }
        } header: {
            Text("Fills")
        } footer: {
            Text("Fees are in USD. Closed quantity cannot exceed opened quantity.")
        }
    }

    private func addFill(_ action: FillAction) {
        var fill = FillDraft()
        fill.action = action
        if let last = fills.last { fill.price = nil; fill.date = max(Date(), last.date) }
        fills.append(fill)
    }
}
