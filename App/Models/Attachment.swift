import Foundation
import SwiftData

@Model
final class Attachment {
    var uuid: UUID = UUID()
    @Attribute(.externalStorage) var imageData: Data?
    var caption: String = ""
    var createdAt: Date = Date()
    var trade: Trade?

    init(uuid: UUID = UUID(), imageData: Data?, caption: String = "", createdAt: Date = Date()) {
        self.uuid = uuid
        self.imageData = imageData
        self.caption = caption
        self.createdAt = createdAt
    }
}
