import AppKit

// Convert the approved artwork into the standard macOS icon representations.
guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: make-icon.swift <output.iconset> <source.png>")
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let source = URL(fileURLWithPath: CommandLine.arguments[2])
guard let image = NSImage(contentsOf: source) else { fatalError("Cannot load icon artwork") }
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func writeRepresentation(size: Int, filename: String) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("Cannot create icon bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero,
               operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
    try png.write(to: output.appendingPathComponent(filename))
}
for base in [16, 32, 128, 256, 512] {
    try writeRepresentation(size: base, filename: "icon_\(base)x\(base).png")
    try writeRepresentation(size: base * 2, filename: "icon_\(base)x\(base)@2x.png")
}
