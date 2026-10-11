import AppKit

// Text overlays stay separate from the genuine footage. AppKit avoids requiring
// an FFmpeg build with the optional drawtext filter.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let ink = NSColor(srgbRed: 38/255, green: 54/255, blue: 44/255, alpha: 1)

struct Label {
    let text: String
    let size: CGFloat
    let x: CGFloat
    let top: CGFloat
    var serif = false
    var bold = false
}

func render(_ name: String, width: Int, height: Int, labels: [Label]) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.shouldAntialias = true
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    for label in labels {
        let font = label.serif ? NSFont(name: "Georgia", size: label.size)!
            : NSFont.systemFont(ofSize: label.size, weight: label.bold ? .semibold : .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 12
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph]
        let available = CGFloat(width) - label.x - 35
        let bounds = (label.text as NSString).boundingRect(with: NSSize(width: available, height: CGFloat(height)),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
        (label.text as NSString).draw(in: NSRect(x: label.x, y: CGFloat(height) - label.top - ceil(bounds.height),
            width: available, height: ceil(bounds.height)), withAttributes: attributes)
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}

try render("vertical.png", width: 1080, height: 1920, labels: [
    Label(text: "Sweep it\nunder the rug.", size: 105, x: 70, top: 120, serif: true),
    Label(text: "Hide the mess. Your files stay put.", size: 38, x: 70, top: 1500),
    Label(text: "Free  /  macOS 14+  /  Apple Silicon", size: 29, x: 70, top: 1580),
    Label(text: "github.com/ShabanovBoris/DesktopRug", size: 28, x: 70, top: 1735, bold: true)
])
for (index, text) in [(1, "01 / A messy desktop?"), (2, "02 / Sweep it under the rug."), (3, "03 / Lift a corner. It's all still there.")] {
    try render("gallery-\(index).png", width: 1270, height: 760,
        labels: [Label(text: text, size: 38, x: 115, top: 15, serif: true)])
}
try render("social.png", width: 1200, height: 630, labels: [
    Label(text: "DESKTOP RUG", size: 16, x: 52, top: 70, bold: true),
    Label(text: "Sweep it\nunder\nthe rug.", size: 68, x: 52, top: 145, serif: true),
    Label(text: "Free. Native. Open source.", size: 18, x: 52, top: 535)
])
