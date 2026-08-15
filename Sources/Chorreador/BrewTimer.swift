import Foundation

enum BrewTimerOption: Int, CaseIterable, Identifiable {
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .thirtyMinutes: return "30 min"
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        }
    }

    var duration: TimeInterval {
        TimeInterval(rawValue * 60)
    }
}
