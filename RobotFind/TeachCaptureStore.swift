import Foundation
import AVFoundation

enum TeachCaptureError: LocalizedError {
    case applicationSupportUnavailable
    case invalidItemID
    case invalidClip(URL)
    case incompleteClips(Int)

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "The app storage directory is unavailable."
        case .invalidItemID:
            return "The teaching item identifier is invalid."
        case .invalidClip(let url):
            return "The recorded clip is invalid: \(url.lastPathComponent)."
        case .incompleteClips(let count):
            return "Only \(count) valid clips were recorded."
        }
    }
}

struct TeachVideoClip {
    let index: Int
    let url: URL
    let duration: TimeInterval
    let fileSize: Int64
}

/// Owns the local MP4 file layout for one teaching item.
final class TeachCaptureStore {
    static let shared = TeachCaptureStore()

    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "com.robotfind.teach-captures")

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func startSession(itemID: String) throws {
        try queue.sync {
            let directory = try itemDirectory(itemID)
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.removeItem(at: directory)
            }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            print("[TeachVideo] session item=\(itemID)")
        }
    }

    func captureDirectory(itemID: String) throws -> URL {
        try queue.sync {
            let directory = try itemDirectory(itemID)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    func clipURL(itemID: String, index: Int) throws -> URL {
        guard (1...4).contains(index) else { throw TeachCaptureError.invalidItemID }
        return try captureDirectory(itemID: itemID)
            .appendingPathComponent(String(format: "clip_%02d.mp4", index))
    }

    func listClips(itemID: String) throws -> [URL] {
        try queue.sync {
            let directory = try itemDirectory(itemID)
            guard fileManager.fileExists(atPath: directory.path) else { return [] }
            return try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension.lowercased() == "mp4" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
    }

    func validateClips(itemID: String, expectedCount: Int = 4) throws -> [TeachVideoClip] {
        let urls = try listClips(itemID: itemID)
        guard urls.count == expectedCount else {
            throw TeachCaptureError.incompleteClips(urls.count)
        }

        var clips: [TeachVideoClip] = []
        for (offset, url) in urls.enumerated() {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let asset = AVURLAsset(url: url)
            let duration = asset.duration.seconds
            guard fileSize > 0, duration.isFinite, duration > 0,
                  !asset.tracks(withMediaType: .video).isEmpty else {
                throw TeachCaptureError.invalidClip(url)
            }
            clips.append(TeachVideoClip(index: offset + 1, url: url, duration: duration, fileSize: fileSize))
        }
        return clips
    }

    func clear(itemID: String) throws {
        try queue.sync {
            let directory = try itemDirectory(itemID)
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.removeItem(at: directory)
            }
        }
    }

    private func itemDirectory(_ itemID: String) throws -> URL {
        guard !itemID.isEmpty,
              !itemID.contains("/"),
              !itemID.contains("\\"),
              let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw itemID.isEmpty ? TeachCaptureError.applicationSupportUnavailable : TeachCaptureError.invalidItemID
        }
        let root = applicationSupport.appendingPathComponent("TeachCaptures", isDirectory: true)
        if !fileManager.fileExists(atPath: root.path) {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root.appendingPathComponent(itemID, isDirectory: true)
    }
}
