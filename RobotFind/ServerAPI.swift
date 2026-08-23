import Foundation

enum ServerAPIError: LocalizedError {
    case disconnected
    case invalidVideo(URL)
    case invalidResponse
    case httpStatus(Int)
    case invalidProfile(String)
    case requestFailed(String)

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
        }
    }
}

final class ServerAPI {
    private let baseURL: URL
    private let session: URLSession
    private let requestTimeout: TimeInterval = 300

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
            print("[ObjectUpload] failed: \(error.localizedDescription)")
            throw ServerAPIError.requestFailed(error.localizedDescription)
        }
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
