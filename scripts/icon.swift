import AppKit
let sizes = [("Icon60@2x.png", 120), ("Icon60@3x.png", 180), ("Icon1024.png", 1024)]
let directory = CommandLine.arguments[1]
for (name, pixels) in sizes {
    let size = CGFloat(pixels), image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSColor(srgbRed: 9/255, green: 18/255, blue: 36/255, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
    let triangle = NSBezierPath(); triangle.move(to: NSPoint(x: size * 0.37, y: size * 0.27)); triangle.line(to: NSPoint(x: size * 0.75, y: size * 0.5)); triangle.line(to: NSPoint(x: size * 0.37, y: size * 0.73)); triangle.close()
    NSColor(srgbRed: 229/255, green: 9/255, blue: 20/255, alpha: 1).setFill(); triangle.fill()
    image.unlockFocus()
    let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
}
