import Foundation

enum ServerAPIError: LocalizedError {
    case disconnected
    case invalidVideo(URL)
    case invalidResponse
    case httpStatus(Int)
    case invalidProfile(String)
    case requestFailed(String)
    case analysisTimedOut
    case missionAlreadyActive
    case missionObjectNotFound
    case missionInvalid
    case missionUnavailable
    case invalidMissionResponse

    var errorDescription: String? {
        switch self {
        case .disconnected:
            return "Connect to the server before analyzing this item."
        case .invalidVideo(let url):
            return "The recorded video could not be found: \(url.lastPathComponent)."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .httpStatus(let status):
            return "The server could not analyze this item (HTTP \(status))."
        case .invalidProfile(let reason):
            return "The server returned an incomplete item profile: \(reason)"
        case .requestFailed(let reason):
            return "The server could not analyze this item. \(reason)"
        case .analysisTimedOut:
            return "The analysis request timed out. The server may still be processing the item. Your videos were kept locally; wait before retrying."
        case .missionAlreadyActive:
            return "Another robot search is already active."
        case .missionObjectNotFound:
            return "This item is not available on the server."
        case .missionInvalid:
            return "This item cannot be used for a robot search."
        case .missionUnavailable:
            return "The robot search service is unavailable."
        case .invalidMissionResponse:
            return "The server returned an invalid robot mission."
        }
    }
}

final class ServerAPI {
    private let baseURL: URL
    private let session: URLSession
    private let requestTimeout: TimeInterval = 600

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func createObject(name: String, videoURLs: [URL]) async throws -> ObjectProfile {
        guard videoURLs.count == 4 else {
            throw ServerAPIError.requestFailed("Four teaching videos are required.")
        }

        for url in videoURLs {
            guard FileManager.default.fileExists(atPath: url.path),
                  let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber,
                  size.int64Value > 0,
                  url.pathExtension.lowercased() == "mp4" else {
                throw ServerAPIError.invalidVideo(url)
            }
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let body = try makeMultipartBody(name: name, videoURLs: videoURLs, boundary: boundary)
        let endpoint = baseURL.appendingPathComponent("api/v1/objects")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        print("[ObjectUpload] clips=4")
        for url in videoURLs {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            print("[ObjectUpload] \(url.lastPathComponent) size=\(size)")
        }
        print("[ObjectUpload] request start")
        print("[ObjectUpload] timeout=\(Int(requestTimeout))s")

        do {
            let (data, response) = try await session.upload(for: request, from: body)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ServerAPIError.invalidResponse
            }
            print("[ObjectUpload] response status=\(httpResponse.statusCode)")
            guard (200...299).contains(httpResponse.statusCode) else {
                throw ServerAPIError.httpStatus(httpResponse.statusCode)
            }

            let profile: ObjectProfile
            do {
                profile = try ObjectProfile.decoder().decode(ObjectProfile.self, from: data)
            } catch {
                #if DEBUG
                print("[ObjectUpload] ObjectProfile decode failed: \(String(reflecting: error))")
                if let rawBody = String(data: data, encoding: .utf8) {
                    print("[ObjectUpload] raw response body: \(rawBody)")
                } else {
                    print("[ObjectUpload] raw response body (base64): \(data.base64EncodedString())")
                }
                #endif
                throw ServerAPIError.invalidProfile("The response was not valid ObjectProfile JSON.")
            }
            try validate(profile)
            print("[ObjectUpload] object_id=\(profile.objectID)")
            print("[ObjectUpload] category=\(profile.category)")
            print("[ObjectUpload] completed")
            return profile
        } catch let error as ServerAPIError {
            print("[ObjectUpload] failed: \(error.localizedDescription)")
            throw error
        } catch {
            if let urlError = error as? URLError, urlError.code == .timedOut {
                print("[ObjectUpload] timed out after \(Int(requestTimeout))s; server may still be processing")
                throw ServerAPIError.analysisTimedOut
            }
            print("[ObjectUpload] failed: \(error.localizedDescription)")
            throw ServerAPIError.requestFailed(error.localizedDescription)
        }
    }

    func createMission(objectID: String) async throws -> Mission {
        let endpoint = baseURL.appendingPathComponent("api/v1/missions")
        let body = try JSONSerialization.data(withJSONObject: ["object_id": objectID])
        print("[Mission] create request")
        return try await missionRequest(url: endpoint, method: "POST", body: body)
    }

    func startMission(missionID: String) async throws -> Mission {
        let endpoint = baseURL
            .appendingPathComponent("api/v1/missions")
            .appendingPathComponent(missionID)
            .appendingPathComponent("start")
        print("[Mission] start request mission_id=\(missionID)")
        return try await missionRequest(url: endpoint, method: "POST")
    }

    func getMission(missionID: String) async throws -> Mission {
        let endpoint = baseURL
            .appendingPathComponent("api/v1/missions")
            .appendingPathComponent(missionID)
        return try await missionRequest(url: endpoint, method: "GET")
    }

    private func validate(_ profile: ObjectProfile) throws {
        guard !profile.objectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServerAPIError.invalidProfile("object_id is empty.")
        }
        guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServerAPIError.invalidProfile("name is empty.")
        }
        guard !profile.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServerAPIError.invalidProfile("category is empty.")
        }
        guard !profile.visualDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServerAPIError.invalidProfile("visual_description is empty.")
        }
        guard !profile.navigationDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ServerAPIError.invalidProfile("navigation_description is empty.")
        }
    }

    private func missionRequest(url: URL, method: String, body: Data? = nil) async throws -> Mission {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ServerAPIError.invalidMissionResponse
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                switch httpResponse.statusCode {
                case 404: throw ServerAPIError.missionObjectNotFound
                case 409: throw ServerAPIError.missionAlreadyActive
                case 422: throw ServerAPIError.missionInvalid
                case 500...599: throw ServerAPIError.missionUnavailable
                default: throw ServerAPIError.httpStatus(httpResponse.statusCode)
                }
            }

            do {
                return try ObjectProfile.decoder().decode(Mission.self, from: data)
            } catch {
                #if DEBUG
                print("[Mission] decode failed: \(String(reflecting: error))")
                if let rawBody = String(data: data, encoding: .utf8) {
                    print("[Mission] raw response body: \(rawBody)")
                }
                #endif
                throw ServerAPIError.invalidMissionResponse
            }
        } catch let error as ServerAPIError {
            throw error
        } catch {
            throw ServerAPIError.requestFailed(error.localizedDescription)
        }
    }

    private func makeMultipartBody(name: String, videoURLs: [URL], boundary: String) throws -> Data {
        var body = Data()
        let lineBreak = "\r\n"

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        append("--\(boundary)\(lineBreak)")
        append("Content-Disposition: form-data; name=\"name\"\(lineBreak)\(lineBreak)")
        append(name)
        append(lineBreak)

        for url in videoURLs {
            append("--\(boundary)\(lineBreak)")
            append("Content-Disposition: form-data; name=\"videos\"; filename=\"\(url.lastPathComponent)\"\(lineBreak)")
            append("Content-Type: video/mp4\(lineBreak)\(lineBreak)")
            body.append(try Data(contentsOf: url, options: [.mappedIfSafe]))
            append(lineBreak)
        }

        append("--\(boundary)--\(lineBreak)")
        return body
    }
}
