import Foundation

struct ServerHealthResponse: Decodable {
    let status: String?
    let qwenLoaded: Bool?
    let model: String?

    enum CodingKeys: String, CodingKey {
        case status
        case qwenLoaded = "qwen_loaded"
        case model
    }
}

final class ServerHealthClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func check(baseURL: URL) async throws -> ServerHealthResponse {
        let url = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        print("[Health] GET /health")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SSHConnectionError.healthCheckFailed("Invalid HTTP response.")
        }
        print("[Health] status=\(httpResponse.statusCode)")
        guard (200...299).contains(httpResponse.statusCode) else {
            throw SSHConnectionError.healthCheckFailed("HTTP \(httpResponse.statusCode).")
        }

        let decoded: ServerHealthResponse
        do {
            decoded = try JSONDecoder().decode(ServerHealthResponse.self, from: data)
        } catch {
            throw SSHConnectionError.healthCheckFailed("The response was not valid JSON.")
        }
        guard decoded.status?.lowercased() == "ok" else {
            throw SSHConnectionError.healthCheckFailed("The service is not ready.")
        }
        return decoded
    }
}
