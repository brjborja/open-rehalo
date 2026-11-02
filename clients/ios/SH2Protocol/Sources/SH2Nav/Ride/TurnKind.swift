import Foundation

/// The kind of manoeuvre the phone screen announces.
public enum TurnKind: String, CaseIterable, Equatable, Sendable, Codable {
    case straight, slightLeft, left, sharpLeft, slightRight, right, sharpRight, uTurn
    case roundabout, arrival, offRoute

    /// Classify a signed heading change (positive = right). Under 30° it's hardly a turn.
    public init?(turn delta: Double) {
        let a = abs(delta)
        let right = delta > 0
        switch a {
        case ..<30: return nil
        case ..<55: self = right ? .slightRight : .slightLeft
        case ..<125: self = right ? .right : .left
        case ..<165: self = right ? .sharpRight : .sharpLeft
        default: self = .uTurn
        }
    }

    /// A routed turn under 30° (`init?` gives up there): a slight turn, or straight on through a
    /// roundabout or a caution step. A GPX's small angles are not turns and keep the original's text.
    static func gentle(_ delta: Double) -> TurnKind {
        guard abs(delta) >= Double(NavStepFactory.routedTurnMinimum) else { return .straight }
        return delta > 0 ? .slightRight : .slightLeft
    }
}
