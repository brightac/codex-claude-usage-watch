import AppKit

func drawIcon(size s: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    // Rounded-rect dark background (glass look)
    let inset = s * 0.05
    let rect = CGRect(x: inset, y: inset, width: s - 2*inset, height: s - 2*inset)
    let radius = s * 0.225
    let bg = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(bg)
    ctx.setFillColor(NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.19, alpha: 1).cgColor)
    ctx.fillPath()
    // subtle top highlight
    ctx.addPath(bg)
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.10).cgColor)
    ctx.setLineWidth(s * 0.006)
    ctx.strokePath()

    // Gauge ring
    let c = CGPoint(x: s/2, y: s/2)
    let ringR = (s - 2*inset) * 0.30
    let lineW = s * 0.095
    // track
    ctx.setLineCap(.round)
    ctx.setLineWidth(lineW)
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.14).cgColor)
    ctx.addArc(center: c, radius: ringR, startAngle: 0, endAngle: .pi*2, clockwise: false)
    ctx.strokePath()
    // green arc, ~72% from top, clockwise
    let start = CGFloat.pi/2
    let sweep = CGFloat.pi*2 * 0.72
    ctx.setStrokeColor(NSColor(calibratedRed: 0.32, green: 0.85, blue: 0.48, alpha: 1).cgColor)
    ctx.addArc(center: c, radius: ringR, startAngle: start, endAngle: start - sweep, clockwise: true)
    ctx.strokePath()

    img.unlockFocus()
    return img
}

func png(_ img: NSImage, _ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: CGFloat(px)).draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1]
let sizes = [(16,"16x16"),(32,"16x16@2x"),(32,"32x32"),(64,"32x32@2x"),(128,"128x128"),(256,"128x128@2x"),(256,"256x256"),(512,"256x256@2x"),(512,"512x512"),(1024,"512x512@2x")]
for (px, name) in sizes {
    try! png(NSImage(), px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
print("iconset written to \(out)")
