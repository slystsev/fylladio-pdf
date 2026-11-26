import Foundation

/// Where the reader was in a file: page, point on that page, zoom.
public struct ReadingPosition: Codable, Equatable {
    public var page: Int
    public var x: Double
    public var y: Double
    public var scale: Double
    public var autoScales: Bool
    public init(page: Int, x: Double, y: Double, scale: Double, autoScales: Bool) {
        self.page = page; self.x = x; self.y = y; self.scale = scale; self.autoScales = autoScales
    }
}

public enum PositionStore {
    static let key = "Folio.positions"
    static let maxEntries = 500

    public static func get(_ url: URL, defaults: UserDefaults = FolioDefaults.shared) -> ReadingPosition? {
        guard let dict = defaults.dictionary(forKey: key), let data = dict[url.standardizedFileURL.path] as? Data else { return nil }
        return try? JSONDecoder().decode(ReadingPosition.self, from: data)
    }

    public static func set(_ pos: ReadingPosition, for url: URL, defaults: UserDefaults = FolioDefaults.shared) {
        var dict = defaults.dictionary(forKey: key) ?? [:]
        guard let data = try? JSONEncoder().encode(pos) else { return }
        dict[url.standardizedFileURL.path] = data
        if dict.count > maxEntries { dict.removeValue(forKey: dict.keys.first!) }
        defaults.set(dict, forKey: key)
    }
}

/// Folio's settings store. The self-test (FOLIO_SELFTEST set) uses its own suite so it never touches the
/// user's reading positions, open windows or sidebar setting.
public enum FolioDefaults {
    public static let shared: UserDefaults = {
        if ProcessInfo.processInfo.environment["FOLIO_SELFTEST"] != nil, let d = UserDefaults(suiteName: "app.folio.pdf.selftest") {
            d.removePersistentDomain(forName: "app.folio.pdf.selftest")
            return d
        }
        return .standard
    }()
}
