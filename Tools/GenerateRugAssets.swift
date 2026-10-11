import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "DesktopRug/Resources", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

struct Palette {
    var field: NSColor
    var navy: NSColor
    var cream: NSColor
    var gold: NSColor
    var teal: NSColor
    var rust: NSColor
}
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(calibratedRed: r, green: g, blue: b, alpha: 1) }
let garnet = Palette(field: color(0.49, 0.12, 0.15), navy: color(0.10, 0.14, 0.21), cream: color(0.85, 0.77, 0.59), gold: color(0.65, 0.46, 0.25), teal: color(0.29, 0.39, 0.36), rust: color(0.69, 0.31, 0.23))
let indigo = Palette(field: color(0.13, 0.24, 0.32), navy: color(0.07, 0.12, 0.20), cream: color(0.81, 0.81, 0.68), gold: color(0.64, 0.53, 0.30), teal: color(0.34, 0.51, 0.48), rust: color(0.55, 0.28, 0.22))

func polygon(_ points: [CGPoint], fill: NSColor, stroke: NSColor? = nil, width: CGFloat = 1) {
    let path = NSBezierPath()
    path.move(to: points[0])
    for p in points.dropFirst() { path.line(to: p) }
    path.close()
    fill.setFill(); path.fill()
    if let stroke { stroke.setStroke(); path.lineWidth = width; path.stroke() }
}
func diamond(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ fill: NSColor, _ stroke: NSColor? = nil) {
    polygon([CGPoint(x: x - rx, y: y), CGPoint(x: x, y: y + ry), CGPoint(x: x + rx, y: y), CGPoint(x: x, y: y - ry)], fill: fill, stroke: stroke, width: 2)
}
func star(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ p: Palette, _ fill: NSColor, rays: Int = 8) {
    let points = (0..<(rays * 2)).map { i -> CGPoint in
        let a = CGFloat(i) * .pi / CGFloat(rays)
        let r = i % 2 == 0 ? radius : radius * 0.54
        return CGPoint(x: x + cos(a) * r, y: y + sin(a) * r)
    }
    polygon(points, fill: fill, stroke: p.cream, width: max(0.7, radius / 32))
}
func flower(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ p: Palette, rotation: CGFloat = 0) {
    for i in 0..<8 {
        let a = CGFloat(i) * .pi / 4 + rotation
        let dx = cos(a), dy = sin(a)
        let center = CGPoint(x: x + dx * radius * 0.57, y: y + dy * radius * 0.57)
        let tangent = CGPoint(x: -dy * radius * 0.19, y: dx * radius * 0.19)
        polygon([CGPoint(x: x, y: y), CGPoint(x: center.x + tangent.x, y: center.y + tangent.y), CGPoint(x: x + dx * radius, y: y + dy * radius), CGPoint(x: center.x - tangent.x, y: center.y - tangent.y)], fill: i % 2 == 0 ? p.cream : p.rust, stroke: p.navy, width: 0.8)
    }
    diamond(x, y, radius * 0.26, radius * 0.26, p.navy, p.gold)
    diamond(x, y, radius * 0.10, radius * 0.10, p.cream)
}
func vine(_ a: CGPoint, _ b: CGPoint, _ bend: CGFloat, _ p: Palette) {
    let path = NSBezierPath()
    path.move(to: a)
    let c = CGPoint(x: (a.x + b.x) / 2 + bend, y: (a.y + b.y) / 2 - bend)
    path.curve(to: b, controlPoint1: CGPoint(x: c.x, y: a.y), controlPoint2: CGPoint(x: b.x, y: c.y))
    p.gold.setStroke(); path.lineWidth = 1.7; path.stroke()
    let m = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    diamond(m.x, m.y, 5, 9, p.teal, p.cream)
}
func renderRug(_ palette: Palette) -> CGImage {
    let w = 1536, h = 1024
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    ctx.scaleBy(x: 2, y: 2)
    let rect = NSRect(x: 0, y: 0, width: 768, height: 512)
    palette.navy.setFill(); rect.fill()
    let bands: [(CGFloat, NSColor)] = [(4,palette.cream),(7,palette.rust),(12,palette.navy),(18,palette.gold),(22,palette.navy),(58,palette.cream),(63,palette.rust),(69,palette.navy),(76,palette.cream),(80,palette.field)]
    for (inset, fill) in bands { fill.setFill(); rect.insetBy(dx: inset, dy: inset).fill() }
    for x in stride(from: CGFloat(40), through: 730, by: 36) {
        flower(x, 40, 13, palette); flower(x, 472, 13, palette)
        vine(CGPoint(x:x-18,y:40), CGPoint(x:x+18,y:40), 12, palette)
        vine(CGPoint(x:x-18,y:472), CGPoint(x:x+18,y:472), -12, palette)
    }
    for y in stride(from: CGFloat(76), through: 436, by: 36) { flower(40, y, 13, palette); flower(728, y, 13, palette) }
    for x in stride(from: CGFloat(12), through: 758, by: 12) { diamond(x, 13, 3, 3, palette.cream); diamond(x, 499, 3, 3, palette.cream) }
    for y in stride(from: CGFloat(24), through: 492, by: 12) { diamond(13, y, 3, 3, palette.cream); diamond(755, y, 3, 3, palette.cream) }
    for x in stride(from: CGFloat(91), through: 677, by: 16) { diamond(x, 72, 4, 4, palette.rust); diamond(x, 440, 4, 4, palette.rust) }
    for y in stride(from: CGFloat(88), through: 424, by: 16) { diamond(72,y,4,4,palette.rust); diamond(696,y,4,4,palette.rust) }
    for corner in [CGPoint(x:81,y:81),CGPoint(x:687,y:81),CGPoint(x:81,y:431),CGPoint(x:687,y:431)] {
        let sx: CGFloat = corner.x < 384 ? 1 : -1, sy: CGFloat = corner.y < 256 ? 1 : -1
        polygon([corner,CGPoint(x:corner.x+sx*138,y:corner.y),CGPoint(x:corner.x+sx*108,y:corner.y+sy*18),CGPoint(x:corner.x+sx*104,y:corner.y+sy*36),CGPoint(x:corner.x+sx*77,y:corner.y+sy*40),CGPoint(x:corner.x+sx*64,y:corner.y+sy*68),CGPoint(x:corner.x+sx*40,y:corner.y+sy*76),CGPoint(x:corner.x+sx*28,y:corner.y+sy*103),CGPoint(x:corner.x,y:corner.y+sy*126)],fill:palette.cream,stroke:palette.navy,width:3)
        flower(corner.x+sx*39,corner.y+sy*34,21,palette)
        flower(corner.x+sx*84,corner.y+sy*15,13,palette)
        flower(corner.x+sx*14,corner.y+sy*80,12,palette)
    }
    for row in 0..<7 {
        for col in 0..<12 {
            let x = CGFloat(118 + col * 48 + (row % 2) * 24), y = CGFloat(113 + row * 48)
            guard x < 666 && abs(x - 384) / 125 + abs(y - 256) / 125 > 1.20 else { continue }
            flower(x, y, 12, palette, rotation: CGFloat(row % 2) * .pi / 8)
            vine(CGPoint(x:x,y:y+12),CGPoint(x:x+24,y:y+24),8,palette)
            diamond(x+22,y-10,4,7,palette.teal,palette.gold)
        }
    }
    diamond(384,256,148,169,palette.cream,palette.navy)
    diamond(384,256,141,161,palette.navy,palette.gold)
    star(384,256,124,palette,palette.rust)
    star(384,256,104,palette,palette.navy)
    for i in 0..<16 {
        let a = CGFloat(i) * .pi / 8
        flower(384+cos(a)*79,256+sin(a)*79,12,palette,rotation:a)
    }
    star(384,256,62,palette,palette.cream)
    star(384,256,49,palette,palette.field)
    flower(384,256,34,palette)
    diamond(384,256,12,12,palette.navy,palette.gold)
    for y in [CGFloat(92),420] { flower(384,y,11,palette) }
    NSGraphicsContext.restoreGraphicsState()
    let bytes = ctx.data!.assumingMemoryBound(to: UInt8.self)
    for y in 0..<h { for x in 0..<w {
        let hash = UInt32(truncatingIfNeeded: (x &* 374761393) ^ (y &* 668265263))
        let noise = Float((hash ^ (hash >> 13)) & 255) / 255 - 0.5
        let weave: Float = ((x % 4 < 2) == (y % 4 < 2) ? 1.03 : 0.95) + noise * 0.075
        for c in 0..<3 { let i = (y*w+x)*4+c; bytes[i] = UInt8(min(255,max(0,Float(bytes[i])*weave))) }
    } }
    return ctx.makeImage()!
}
func save(_ image: CGImage, _ url: URL) throws {
    let bitmap = NSBitmapImageRep(cgImage: image)
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}
let heriz = renderRug(garnet)
try save(heriz,output.appendingPathComponent("heriz.png"))
try save(renderRug(indigo),output.appendingPathComponent("indigo.png"))
let catalog = output.appendingPathComponent("Assets.xcassets", isDirectory: true)
try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
try JSONSerialization.data(withJSONObject: ["info": ["version": 1, "author": "xcode"]]).write(to: catalog.appendingPathComponent("Contents.json"))
let iconDirectory = catalog.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconDirectory, withIntermediateDirectories: true)
var iconEntries: [[String: String]] = []
for size in [16,32,128,256,512] { for scale in [1,2] {
    let n = size * scale
    let context = CGContext(data: nil,width:n,height:n,bitsPerComponent:8,bytesPerRow:n*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x:CGFloat(n)/1024,y:CGFloat(n)/1024)
    context.setFillColor(CGColor(red:0.07,green:0.10,blue:0.14,alpha:1))
    context.addPath(CGPath(roundedRect:CGRect(x:0,y:0,width:1024,height:1024),cornerWidth:190,cornerHeight:190,transform:nil));context.fillPath()
    context.translateBy(x:512,y:512);context.rotate(by:-.pi/14)
    context.setShadow(offset:CGSize(width:0,height:-26),blur:35,color:CGColor(gray:0,alpha:0.5))
    context.draw(heriz,in:CGRect(x:-365,y:-255,width:730,height:510))
    context.setShadow(offset:.zero,blur:0)
    context.setStrokeColor(garnet.cream.cgColor);context.setLineWidth(4)
    for x in stride(from:CGFloat(-357),through:357,by:12) { context.move(to:CGPoint(x:x,y:-255));context.addLine(to:CGPoint(x:x,y:-275));context.move(to:CGPoint(x:x,y:255));context.addLine(to:CGPoint(x:x,y:275)) }
    context.strokePath()
    let suffix = scale == 2 ? "@2x" : ""
    let filename = "icon_\(size)x\(size)\(suffix).png"
    try save(context.makeImage()!,iconDirectory.appendingPathComponent(filename))
    iconEntries.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
} }
try JSONSerialization.data(withJSONObject: ["images": iconEntries, "info": ["version": 1, "author": "xcode"]], options: .prettyPrinted).write(to: iconDirectory.appendingPathComponent("Contents.json"))
print("Generated two 1536 × 1024 woven patterns and icon set.")
