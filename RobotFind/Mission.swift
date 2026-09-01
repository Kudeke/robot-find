import Foundation

enum MissionState: String, Codable, Hashable {
    case ready
    case starting
    case running
    case verifying
    case resuming
    case stopping
    case stopped
    case failed
    case targetFound = "target_found"

    var isTerminal: Bool {
        switch self {
        case .targetFound, .stopped, .failed:
            return true
        case .ready, .starting, .running, .verifying, .resuming, .stopping:
            return false
        }
    }
}

struct Mission: Codable, Identifiable, Hashable {
    let missionID: String
    let objectID: String
    let objectName: String
    let state: MissionState
    let navigationInstruction: String
    let createdAt: Date
    let error: String?

    var id: String { missionID }

    enum CodingKeys: String, CodingKey {
        case missionID = "mission_id"
        case objectID = "object_id"
        case objectName = "object_name"
        case state
        case navigationInstruction = "navigation_instruction"
        case createdAt = "created_at"
        case error
    }
}
