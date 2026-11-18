import AppKit

let size = NSSize(width: 640, height: 400)
let image = NSImage(size: size)
image.lockFocus()
NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 278, y: 248))
arrow.line(to: NSPoint(x: 362, y: 248))
arrow.move(to: NSPoint(x: 348, y: 262))
arrow.line(to: NSPoint(x: 362, y: 248))
arrow.line(to: NSPoint(x: 348, y: 234))
arrow.lineWidth = 4
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
NSColor(calibratedRed: 0.72, green: 0.53, blue: 0.07, alpha: 1).setStroke()
arrow.stroke()
func centered(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let width = text.size(withAttributes: attributes).width
    text.draw(at: NSPoint(x: (640 - width) / 2, y: y), withAttributes: attributes)
}
centered("Drag to install", y: 78, font: .systemFont(ofSize: 20, weight: .medium), color: .darkGray)
centered("BananaCursor", y: 42, font: .systemFont(ofSize: 13), color: .gray)
image.unlockFocus()
try image.tiffRepresentation!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
