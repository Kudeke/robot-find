import Foundation
import CoreImage
import CoreGraphics
import UIKit

enum TeachCaptureError: LocalizedError {
    case applicationSupportUnavailable
    case invalidImage
    case insufficientImages(Int)

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "The app storage directory is unavailable."
        case .invalidImage:
            return "The camera frame could not be converted to JPEG."
        case .insufficientImages(let count):
            return "Only \(count) usable images were captured."
        }
    }
}

/// Stores the local image set produced by one guided teaching session.
final class TeachCaptureStore {
    static let shared = TeachCaptureStore()

    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "com.robotfind.teach-captures")
    private let ciContext = CIContext()

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
            print("[TeachCapture] session started item=\(itemID)")
        }
    }

    @discardableResult
    func appendJPEGData(_ data: Data, itemID: String) throws -> URL {
        try queue.sync {
            let directory = try itemDirectory(itemID)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let nextIndex = try nextIndex(in: directory)
            let url = directory.appendingPathComponent(String(format: "%03d.jpg", nextIndex))
            try data.write(to: url, options: [.atomic])
            print("[TeachCapture] saved \(url.lastPathComponent)")
            return url
        }
    }

    func appendJPEG(from pixelBuffer: CVPixelBuffer, itemID: String, quality: CGFloat = 0.82) throws {
        guard let data = jpegData(from: pixelBuffer, quality: quality) else {
            throw TeachCaptureError.invalidImage
        }
        try appendJPEGData(data, itemID: itemID)
    }

    func loadImages(itemID: String) throws -> [URL] {
        try queue.sync {
            let directory = try itemDirectory(itemID)
            guard fileManager.fileExists(atPath: directory.path) else { return [] }
            return try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
    }

    func imageCount(itemID: String) throws -> Int {
        try loadImages(itemID: itemID).count
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
              let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw TeachCaptureError.applicationSupportUnavailable
        }
        let root = applicationSupport.appendingPathComponent("TeachCaptures", isDirectory: true)
        if !fileManager.fileExists(atPath: root.path) {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root.appendingPathComponent(itemID, isDirectory: true)
    }

    private func nextIndex(in directory: URL) throws -> Int {
        let names = try fileManager.contentsOfDirectory(atPath: directory.path)
        let indexes = names.compactMap { name -> Int? in
            guard name.lowercased().hasSuffix(".jpg") else { return nil }
            return Int(name.dropLast(4))
        }
        return (indexes.max() ?? 0) + 1
    }

    private func jpegData(from pixelBuffer: CVPixelBuffer, quality: CGFloat) -> Data? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
            .oriented(.right)
        let scale = min(1, 1280 / max(image.extent.width, image.extent.height))
        let scaled = scale < 1
            ? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : image
        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: quality)
    }
}
