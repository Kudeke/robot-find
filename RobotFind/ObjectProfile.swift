import Foundation

struct ObjectProfile: Codable, Hashable {
    let objectID: String
    let name: String
    let category: String
    let visualDescription: String
    let distinctiveFeatures: [String]
    let navigationDescription: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case objectID = "object_id"
        case name
        case category
        case visualDescription = "visual_description"
        case distinctiveFeatures = "distinctive_features"
        case navigationDescription = "navigation_description"
        case createdAt = "created_at"
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: timestamp)
            }
            let value = try container.decode(String.self)
            guard let date = parseISO8601(value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO-8601 date: \(value)"
                )
            }
            return date
        }
        return decoder
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }

        // Parse the fractional component separately so microseconds are accepted.
        guard let decimal = value.firstIndex(of: ".") else { return nil }
        let fractionStart = value.index(after: decimal)
        let suffixStart = value[fractionStart...].firstIndex { character in
            character == "Z" || character == "+" || character == "-"
        } ?? value.endIndex
        let fraction = String(value[fractionStart..<suffixStart])
        guard !fraction.isEmpty,
              fraction.allSatisfy(\.isNumber),
              let fractionValue = Double("0.\(fraction)") else {
            return nil
        }

        let baseValue = String(value[..<decimal]) + String(value[suffixStart...])
        guard let baseDate = formatter.date(from: baseValue) else { return nil }
        return baseDate.addingTimeInterval(fractionValue)
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
