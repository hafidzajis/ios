import Foundation

enum Emotion: String, CaseIterable, Identifiable {
    case calm = "Calm"
    case confident = "Confident"
    case fomo = "FOMO"
    case fearful = "Fearful"
    case greedy = "Greedy"
    case revenge = "Revenge"
    case bored = "Bored"

    var id: String { rawValue }
}
