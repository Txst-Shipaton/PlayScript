import Foundation

public struct ChoiceReflection: Sendable {
    public let character: String
    public let title: String
    public let explanation: String
    public let traits: [String]
    public let moments: [String]

    public init(decisions: [String: String]) {
        let meanings: [String: (String, String, Bool)] = [
            "answer": ("Openness", "At the window, you stepped into the light and let yourself be seen.", true),
            "listen": ("Thoughtfulness", "At the window, you listened before trusting your heart.", false),
            "certain": ("Conviction", "You answered the vow with a wholehearted promise.", true),
            "sure": ("Discernment", "You asked for a promise with a future, not just beautiful words.", false),
            "resolve": ("Resolve", "Facing the vial, you reached toward tomorrow with determination.", true),
            "afraid": ("Vulnerability", "Facing the vial, you made room for fear and found courage within it.", false),
        ]
        let choices = ["window-choice", "vow-choice", "potion-choice"].compactMap { decisions[$0] }.compactMap { meanings[$0] }
        traits = choices.map { $0.0 }
        moments = choices.map { $0.1 }
        let bold = choices.filter { $0.2 }.count
        character = choices.isEmpty ? "An unwritten heart" : bold >= 2 ? "Romeo" : "Juliet"
        title = choices.isEmpty ? "A new reading awaits" : bold >= 2 ? "The wholehearted romantic" : "The quietly courageous"
        explanation = choices.isEmpty
            ? "Read again and make your choices to discover your reflection."
            : bold >= 2
                ? "Your choices echo Romeo’s open-hearted intensity: you tend to step forward, speak honestly, and trust a promise."
                : "Your choices echo Juliet’s reflective courage: you listen closely, seek sincerity, and keep loving even when you feel afraid."
    }
}

public extension StoryChoice {
    var responseTitle: String {
        switch id {
        case "answer": "You let yourself be seen"
        case "listen": "You gave trust a little time"
        case "certain": "Your certainty became a promise"
        case "sure": "You asked love to mean it"
        case "resolve": "You reached for tomorrow"
        case "afraid": "You carried fear with courage"
        default: "Your heart answered"
        }
    }
    var isBold: Bool { ["answer", "certain", "resolve"].contains(id) }
}
