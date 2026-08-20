// FeaturePrintStore.swift
// Persists VNFeaturePrintObservation arrays keyed by item ID.

import Foundation
import Vision

final class FeaturePrintStore {
    static let shared = FeaturePrintStore()
    private init() {}

    private var storeDirectory: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FeaturePrints", isDirectory: true)
    }

    func save(_ observations: [VNFeaturePrintObservation], for itemID: String) {
        let dir = storeDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: observations as NSArray,
            requiringSecureCoding: true
        ) else { return }
        try? data.write(to: fileURL(for: itemID), options: .atomic)
    }

    func load(for itemID: String) -> [VNFeaturePrintObservation] {
        guard let data = try? Data(contentsOf: fileURL(for: itemID)) else { return [] }
        let result = try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSArray.self, VNFeaturePrintObservation.self],
            from: data
        )
        return (result as? [VNFeaturePrintObservation]) ?? []
    }

    func delete(for itemID: String) {
        try? FileManager.default.removeItem(at: fileURL(for: itemID))
    }

    func hasPrints(for itemID: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: itemID).path)
    }

    private func fileURL(for itemID: String) -> URL {
        storeDirectory.appendingPathComponent("\(itemID).prints")
    }
}
