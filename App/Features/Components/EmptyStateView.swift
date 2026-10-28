import SwiftUI

struct EmptyStateView: View {
    let title: String
    var systemImage: String = "tray"
    var message: String?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message { Text(message) }
        }
    }
}
