import Foundation
import SwiftData

enum TagKind: String, CaseIterable, Identifiable {
    case indicator, custom, mistake
    var id: String { rawValue }
    var title: String {
        switch self {
        case .indicator: return "Indicator"
        case .custom: return "Custom"
        case .mistake: return "Mistake"
        }
    }
}

@Model
final class Tag {
    var uuid: UUID = UUID()
    var name: String = ""
    var kindRaw: String = TagKind.custom.rawValue
    var colorHex: String = "#0A84FF"
    var trades: [Trade]?

    var kind: TagKind {
        get { TagKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }

    init(name: String, kind: TagKind = .custom, colorHex: String = "#0A84FF") {
        self.uuid = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.colorHex = colorHex
    }
}
