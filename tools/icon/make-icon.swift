// Renders the EasyControl app icon: hand landmarks of a pinch (thumb + index) meeting inside the cursor ring.
// Usage: swift tools/icon/make-icon.swift App/Resources/AppIcon.icns
import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
let cg = ctx.cgContext
let space = CGColorSpaceCreateDeviceRGB()
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: space, components: [r, g, b, a])! }

// macOS icon grid: 824 pt squircle on a 1024 canvas, soft shadow underneath.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(0, 0, 0, 0.35))
cg.addPath(squircle); cg.setFillColor(color(0.1, 0.1, 0.2)); cg.fillPath()
cg.restoreGState()

cg.saveGState()
cg.addPath(squircle); cg.clip()
let bg = CGGradient(colorsSpace: space, colors: [color(0.40, 0.30, 0.95), color(0.10, 0.12, 0.36)] as CFArray, locations: [0, 1])!
cg.drawLinearGradient(bg, start: CGPoint(x: 200, y: 924), end: CGPoint(x: 824, y: 100), options: [])
let glow = CGGradient(colorsSpace: space, colors: [color(0.35, 0.85, 1.0, 0.45), color(0.35, 0.85, 1.0, 0)] as CFArray, locations: [0, 1])!
cg.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 580), startRadius: 0, endCenter: CGPoint(x: 512, y: 580), endRadius: 430, options: [])

let contact = CGPoint(x: 512, y: 590)
let index: [CGPoint] = [CGPoint(x: 735, y: 215), CGPoint(x: 672, y: 355), CGPoint(x: 600, y: 480), contact]
let thumb: [CGPoint] = [CGPoint(x: 300, y: 235), CGPoint(x: 360, y: 370), CGPoint(x: 435, y: 485), contact]

// Cursor ring around the contact point.
cg.setStrokeColor(color(1, 1, 1, 0.92)); cg.setLineWidth(26)
cg.strokeEllipse(in: CGRect(x: contact.x - 175, y: contact.y - 175, width: 350, height: 350))

// Skeleton bones and joints.
func chain(_ pts: [CGPoint], tint: CGColor) {
    cg.setStrokeColor(tint); cg.setLineWidth(22); cg.setLineCap(.round); cg.setLineJoin(.round)
    cg.beginPath(); cg.move(to: pts[0]); pts.dropFirst().forEach { cg.addLine(to: $0) }; cg.strokePath()
    for p in pts.dropLast() {
        cg.setFillColor(color(1, 1, 1)); cg.fillEllipse(in: CGRect(x: p.x - 30, y: p.y - 30, width: 60, height: 60))
        cg.setFillColor(tint); cg.fillEllipse(in: CGRect(x: p.x - 15, y: p.y - 15, width: 30, height: 30))
    }
}
let cyan = color(0.30, 0.82, 1.0), pink = color(1.0, 0.55, 0.85)
chain(index, tint: cyan)
chain(thumb, tint: pink)

// The touch point.
cg.saveGState()
cg.setShadow(offset: .zero, blur: 40, color: color(0.6, 0.95, 1, 1))
cg.setFillColor(color(1, 1, 1)); cg.fillEllipse(in: CGRect(x: contact.x - 44, y: contact.y - 44, width: 88, height: 88))
cg.restoreGState()
cg.restoreGState()

// Subtle top highlight.
cg.saveGState(); cg.addPath(squircle); cg.clip()
cg.setStrokeColor(color(1, 1, 1, 0.18)); cg.setLineWidth(4)
cg.addPath(CGPath(roundedRect: tile.insetBy(dx: 2, dy: 2), cornerWidth: 184, cornerHeight: 184, transform: nil)); cg.strokePath()
cg.restoreGState()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let tmp = NSTemporaryDirectory() + "EasyControl.iconset"
try? FileManager.default.removeItem(atPath: tmp)
try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
let master = rep.representation(using: .png, properties: [:])!
try master.write(to: URL(fileURLWithPath: out.replacingOccurrences(of: ".icns", with: ".png")))
for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let px = pt * scale
    let r = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: r)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSImage(data: master)!.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    try r.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(tmp)/icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"))
}
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", tmp, "-o", out]; try p.run(); p.waitUntilExit()
print("wrote \(out)")
