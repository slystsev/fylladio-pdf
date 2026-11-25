import AppKit

public enum ToolKind: String, Codable {
    case select, marker, underline, squiggly, text
}

/// One preconfigured "stationery" item: a marker, pen or text pen with a fixed colour.
public struct ToolSpec: Codable, Equatable {
    public var id: String
    public var kind: ToolKind
    public var name: String
    /// Hex colour: "RRGGBB" or "RRGGBBAA".
    public var color: String
    /// Single-character shortcut, e.g. "1".
    public var key: String?
    /// Font size for text tools (points).
    public var fontSize: Double?

    public init(id: String, kind: ToolKind, name: String, color: String, key: String?, fontSize: Double? = nil) {
        self.id = id; self.kind = kind; self.name = name; self.color = color; self.key = key; self.fontSize = fontSize
    }

    public var nsColor: NSColor { NSColor(hex: color) ?? .systemYellow }

    public static let pointer = ToolSpec(id: "pointer", kind: .select, name: "Pointer", color: "000000", key: nil)
}

public enum ToolConfig {
    public static let defaults: [ToolSpec] = [
        ToolSpec(id: "marker-yellow", kind: .marker, name: "Yellow marker", color: "FFE13366", key: "1"),
        ToolSpec(id: "marker-green", kind: .marker, name: "Green marker", color: "7CE06A66", key: "2"),
        ToolSpec(id: "marker-pink", kind: .marker, name: "Pink marker", color: "FF7EB966", key: "3"),
        ToolSpec(id: "marker-blue", kind: .marker, name: "Blue marker", color: "6FC3FF66", key: "4"),
        ToolSpec(id: "underline-red", kind: .underline, name: "Red underline", color: "E0262B", key: "5"),
        ToolSpec(id: "underline-blue", kind: .underline, name: "Blue underline", color: "1F5FD6", key: "6"),
        ToolSpec(id: "squiggly-red", kind: .squiggly, name: "Red squiggle", color: "E0262B", key: "7"),
        ToolSpec(id: "squiggly-blue", kind: .squiggly, name: "Blue squiggle", color: "1F5FD6", key: "8"),
        ToolSpec(id: "text-black", kind: .text, name: "Black text", color: "111111", key: "9", fontSize: 12),
        ToolSpec(id: "text-red", kind: .text, name: "Red text", color: "D0201F", key: "0", fontSize: 12),
    ]

    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Folio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var fileURL: URL { supportDirectory.appendingPathComponent("tools.json") }

    /// Loads tools.json, writing defaults on first run. Falls back to defaults on any error.
    public static func load() -> [ToolSpec] {
        let url = fileURL
        if let data = try? Data(contentsOf: url) {
            if let tools = try? JSONDecoder().decode([ToolSpec].self, from: data), !tools.isEmpty {
                return tools
            }
            NSLog("Folio: tools.json unreadable, using defaults")
            return defaults
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(defaults) { try? data.write(to: url, options: .atomic) }
        return defaults
    }
}

public extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: CGFloat
        if s.count == 6 {
            r = CGFloat((v >> 16) & 0xFF) / 255; g = CGFloat((v >> 8) & 0xFF) / 255; b = CGFloat(v & 0xFF) / 255; a = 1
        } else {
            r = CGFloat((v >> 24) & 0xFF) / 255; g = CGFloat((v >> 16) & 0xFF) / 255
            b = CGFloat((v >> 8) & 0xFF) / 255; a = CGFloat(v & 0xFF) / 255
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
