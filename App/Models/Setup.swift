import Foundation
import SwiftData

/// A trading playbook / setup.
@Model
final class Setup {
    var uuid: UUID = UUID()
    var name: String = ""
    var details: String = ""
    @Relationship(inverse: \Trade.setup)
    var trades: [Trade]?

    init(name: String, details: String = "") {
        self.uuid = UUID()
        self.name = name
        self.details = details
    }
}
