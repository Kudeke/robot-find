import Foundation

enum FMTItemStore {
    private static let storageKey = "fmt.items"

    static func load() -> [FMTItem] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return FMTItem.seed
        }

        do {
            let items = try ObjectProfile.decoder().decode([FMTItem].self, from: data)
            for item in items {
                if let profile = item.objectProfile {
                    print("[ItemStore] loaded item=\(item.id) serverObjectID=\(profile.objectID)")
                }
            }
            return items
        } catch {
            print("[ItemStore] load failed: \(String(reflecting: error))")
            return FMTItem.seed
        }
    }

    static func save(_ items: [FMTItem]) throws {
        let data = try JSONEncoder().encode(items)
        UserDefaults.standard.set(data, forKey: storageKey)
        for item in items {
            if let profile = item.objectProfile {
                print("[ItemStore] profile attached localItem=\(item.id)")
                print("[ItemStore] serverObjectID=\(profile.objectID)")
            }
        }
        print("[ItemStore] items persisted")
    }
}
