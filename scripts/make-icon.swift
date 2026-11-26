// Draws Folio's app icon (a page with a marker stroke, an aqua underline and a red ribbon bookmark)
// and writes Resources/Folio.icns. Run: swift scripts/make-icon.swift
import AppKit

func draw(_ s: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s), pixelsHigh: Int(s), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let u = s / 1024
    // macOS icon grid: 824 pt rounded square centred in 1024.
    let tile = NSRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * u, yRadius: 185 * u)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowBlurRadius = 18 * u; shadow.shadowOffset = NSSize(width: 0, height: -8 * u)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25); shadow.set()
    NSColor(srgbRed: 0.16, green: 0.36, blue: 0.62, alpha: 1).setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.45, blue: 0.75, alpha: 1),
               ending: NSColor(srgbRed: 0.10, green: 0.27, blue: 0.50, alpha: 1))!.draw(in: shape, angle: -90)
    // The page
    let page = NSRect(x: 250 * u, y: 190 * u, width: 524 * u, height: 650 * u)
    NSGraphicsContext.saveGraphicsState()
    let ps = NSShadow(); ps.shadowBlurRadius = 20 * u; ps.shadowOffset = NSSize(width: 0, height: -10 * u)
    ps.shadowColor = NSColor.black.withAlphaComponent(0.35); ps.set()
    NSColor(srgbRed: 0.99, green: 0.98, blue: 0.95, alpha: 1).setFill()
    NSBezierPath(roundedRect: page, xRadius: 18 * u, yRadius: 18 * u).fill()
    NSGraphicsContext.restoreGraphicsState()
    // Text lines
    let lineX = page.minX + 60 * u, lineW = page.width - 120 * u
    let ys: [CGFloat] = [720, 650, 580, 510, 440, 370, 300]
    let widths: [CGFloat] = [0.7, 0.68, 0.8, 0.75, 1, 0.95, 0.6]
    for (i, y) in ys.enumerated() {
        // Yellow marker over the third line (drawn under the text bar)
        if i == 2 {
            NSColor(srgbRed: 1, green: 0.85, blue: 0.2, alpha: 0.85).setFill()
            NSBezierPath(roundedRect: NSRect(x: lineX - 14 * u, y: y * u - 20 * u, width: lineW * 0.85 + 28 * u, height: 52 * u), xRadius: 10 * u, yRadius: 10 * u).fill()
        }
        NSColor(white: 0.55, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: lineX, y: y * u, width: lineW * widths[i], height: 14 * u), xRadius: 7 * u, yRadius: 7 * u).fill()
    }
    // Aqua underline under the fifth line
    let ul = NSBezierPath(); ul.lineWidth = 12 * u; ul.lineCapStyle = .round
    ul.move(to: NSPoint(x: lineX, y: 412 * u)); ul.line(to: NSPoint(x: lineX + lineW * 0.8, y: 412 * u))
    NSColor(srgbRed: 0, green: 0.59, blue: 1, alpha: 1).setStroke(); ul.stroke()
    // Red ribbon bookmark from the top edge
    let rx = page.maxX - 130 * u, rw = 70 * u, top = page.maxY + 30 * u, bottom = page.maxY - 230 * u
    let ribbon = NSBezierPath()
    ribbon.move(to: NSPoint(x: rx, y: top)); ribbon.line(to: NSPoint(x: rx + rw, y: top))
    ribbon.line(to: NSPoint(x: rx + rw, y: bottom)); ribbon.line(to: NSPoint(x: rx + rw / 2, y: bottom + 40 * u))
    ribbon.line(to: NSPoint(x: rx, y: bottom)); ribbon.close()
    NSColor(srgbRed: 0.85, green: 0.13, blue: 0.15, alpha: 1).setFill(); ribbon.fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Folio.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! draw(px).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
try! draw(1024).representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("Resources/Folio-1024.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/Folio.icns").path]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "wrote Resources/Folio.icns" : "iconutil failed")
