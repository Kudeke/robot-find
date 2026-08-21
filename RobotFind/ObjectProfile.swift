import Foundation

struct ObjectProfile: Codable, Hashable {
    let objectID: String
    let name: String
    let category: String
    let visualDescription: String
    let distinctiveFeatures: [String]
    let navigationDescription: String
    let createdAt: Date

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date")
        }
        return decoder
    }
}

enum TeachAnalysisState: Equatable {
    case idle
    case validatingVideos
    case analyzing
    case completed(ObjectProfile)
    case failed(String)

    var isWorking: Bool {
        switch self {
        case .validatingVideos, .analyzing: return true
        default: return false
        }
    }
}
