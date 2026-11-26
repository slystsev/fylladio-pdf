import AppKit

public enum ToolKind: String, Codable, CaseIterable {
    case select, marker, underline, squiggly, pen, text

    /// Kinds the user can configure, in palette order.
    public static let configurable: [ToolKind] = [.marker, .underline, .squiggly, .pen, .text]

    public var groupName: String {
        switch self {
        case .select: return "Pointer"
        case .marker: return "Markers"
        case .underline: return "Underline"
        case .squiggly: return "Curly underline"
        case .pen: return "Pens"
        case .text: return "Text"
        }
    }
}

/// One preconfigured "stationery" item: a marker, pen or text pen with fixed settings.
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
    /// Font family/name for text tools.
    public var fontName: String?
    /// Line width for underline / curly / pen tools (points).
    public var width: Double?

    public init(id: String, kind: ToolKind, name: String, color: String, key: String?,
                fontSize: Double? = nil, fontName: String? = nil, width: Double? = nil) {
        self.id = id; self.kind = kind; self.name = name; self.color = color; self.key = key
        self.fontSize = fontSize; self.fontName = fontName; self.width = width
    }

    public var nsColor: NSColor { NSColor(hex: color) ?? .systemYellow }
    public var lineWidth: CGFloat { CGFloat(width ?? (kind == .pen ? 1.5 : 1.0)) }

    public static let pointer = ToolSpec(id: "pointer", kind: .select, name: "Pointer", color: "000000", key: nil)
}

public enum ToolConfig {
    public static let maxPerKind = 5

    public static let defaults: [ToolSpec] = [
        ToolSpec(id: "marker-yellow", kind: .marker, name: "Yellow marker", color: "FFE13366", key: "1"),
        ToolSpec(id: "marker-green", kind: .marker, name: "Green marker", color: "7CE06A66", key: "2"),
        ToolSpec(id: "marker-pink", kind: .marker, name: "Pink marker", color: "FF7EB966", key: "3"),
        ToolSpec(id: "marker-blue", kind: .marker, name: "Blue marker", color: "6FC3FF66", key: "4"),
        ToolSpec(id: "underline-red", kind: .underline, name: "Red underline", color: "E0262B", key: "5", width: 1.25),
        ToolSpec(id: "underline-blue", kind: .underline, name: "Blue underline", color: "0096FF", key: "6", width: 1.25),
        ToolSpec(id: "squiggly-red", kind: .squiggly, name: "Red squiggle", color: "E0262B", key: "7", width: 1.0),
        ToolSpec(id: "squiggly-blue", kind: .squiggly, name: "Blue squiggle", color: "0096FF", key: "8", width: 1.0),
        ToolSpec(id: "pen-black", kind: .pen, name: "Black pen", color: "111111", key: "q", width: 1.5),
        ToolSpec(id: "pen-red", kind: .pen, name: "Red pen", color: "D0201F", key: "w", width: 1.5),
        ToolSpec(id: "pen-blue", kind: .pen, name: "Blue pen", color: "0096FF", key: "e", width: 1.5),
        // Sizes for an A4 study book: blue about body-text size, red small enough to fit between printed lines.
        ToolSpec(id: "text-blue", kind: .text, name: "Blue text", color: "0096FF", key: "9", fontSize: 11, fontName: "Helvetica"),
        ToolSpec(id: "text-red", kind: .text, name: "Red text (between lines)", color: "D0201F", key: "0", fontSize: 7, fontName: "Helvetica"),
    ]

    public static var supportDirectory: URL {
        // Tests (FYLLADIO_SELFTEST=<dir>) get their own folder: they must never create the user's, or the
        // one-time migration from Folio would find it and skip the user's tools.
        let dir = ProcessInfo.processInfo.environment["FYLLADIO_SELFTEST"].map { URL(fileURLWithPath: $0).appendingPathComponent("Support", isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Fylladio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var fileURL: URL { supportDirectory.appendingPathComponent("tools.json") }

    /// Loads tools.json, writing defaults on first run. Kinds missing from the file (e.g. pens added in a
    /// later version) get their defaults, since every kind must have at least one tool.
    public static func load(from url: URL = fileURL) -> [ToolSpec] {
        guard let data = try? Data(contentsOf: url) else {
            try? save(defaults, to: url)
            return defaults
        }
        guard var tools = try? JSONDecoder().decode([ToolSpec].self, from: data), !tools.isEmpty else {
            NSLog("Fylladio: tools.json unreadable, using defaults")
            return defaults
        }
        let usedKeys = Set(tools.compactMap(\.key))
        for kind in ToolKind.configurable where !tools.contains(where: { $0.kind == kind }) {
            for var t in defaults where t.kind == kind {
                if let k = t.key, usedKeys.contains(k) { t.key = nil }
                tools.append(t)
            }
        }
        return normalized(tools)
    }

    public static func save(_ tools: [ToolSpec], to url: URL = fileURL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(normalized(tools)).write(to: url, options: .atomic)
    }

    /// Groups by kind in palette order, at most `maxPerKind` each.
    public static func normalized(_ tools: [ToolSpec]) -> [ToolSpec] {
        ToolKind.configurable.flatMap { k in tools.filter { $0.kind == k }.prefix(maxPerKind) }
    }

    /// Problems that block saving a tool set, as user-facing sentences. Empty when valid.
    public static func validate(_ tools: [ToolSpec]) -> [String] {
        var problems: [String] = []
        for k in ToolKind.configurable {
            let n = tools.filter { $0.kind == k }.count
            if n == 0 { problems.append("\(k.groupName) needs at least one tool.") }
            if n > maxPerKind { problems.append("\(k.groupName) can have at most \(maxPerKind) tools.") }
        }
        var seen: [String: String] = [:]
        for t in tools {
            guard let k = t.key?.lowercased(), !k.isEmpty else { continue }
            if k.count != 1 { problems.append("Shortcut for “\(t.name)” must be a single character."); continue }
            if k == "v" { problems.append("“V” is reserved for the pointer (\(t.name)).") }
            if let other = seen[k] { problems.append("Shortcut “\(k)” is used by both “\(other)” and “\(t.name)”.") }
            seen[k] = t.name
        }
        return problems
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

    /// "RRGGBBAA" in sRGB.
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "%02X%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)), Int(round(c.alphaComponent * 255)))
    }
}
