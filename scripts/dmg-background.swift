// Draws the .dmg window background (600x400): an arrow from the app to Applications, and the install text.
// Usage: swift scripts/dmg-background.swift <out.png>
import AppKit
let out = CommandLine.arguments[1]
let w = 600, h = 400
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(white: 0.97, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
// Arrow between the icons (icons sit at y = 230 from the top -> 170 from the bottom).
let gray = NSColor(white: 0.45, alpha: 1)
gray.setStroke(); gray.setFill()
let line = NSBezierPath(); line.lineWidth = 4; line.lineCapStyle = .round
line.move(to: NSPoint(x: 245, y: 230)); line.line(to: NSPoint(x: 345, y: 230)); line.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 360, y: 230)); head.line(to: NSPoint(x: 340, y: 242)); head.line(to: NSPoint(x: 340, y: 218)); head.close(); head.fill()
// Text
let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineSpacing = 4
let big: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: NSColor(white: 0.15, alpha: 1), .paragraphStyle: para]
let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(white: 0.3, alpha: 1), .paragraphStyle: para]
NSAttributedString(string: "Drag FloatNote to Applications.", attributes: big).draw(in: NSRect(x: 30, y: 90, width: 540, height: 26))
NSAttributedString(string: "First open: if macOS blocks it, go to System Settings > Privacy & Security\nand click Open Anyway.", attributes: small)
    .draw(in: NSRect(x: 30, y: 30, width: 540, height: 50))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
