import AppKit
import CoreGraphics

final class ProbePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ProbeView: NSView {
    var clickCount = 0
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.42, green: 0.06, blue: 0.09, alpha: 1).setFill()
        bounds.fill()
        for inset in stride(from: 8.0, through: 52.0, by: 8.0) {
            (Int(inset) % 16 == 0 ? NSColor.systemYellow : NSColor(calibratedRed: 0.07, green: 0.12, blue: 0.20, alpha: 1)).setStroke()
            let path = NSBezierPath(rect: bounds.insetBy(dx: inset, dy: inset))
            path.lineWidth = 5
            path.stroke()
        }
        for x in stride(from: 75.0, to: bounds.width - 55, by: 35) {
            for y in stride(from: 65.0, to: bounds.height - 55, by: 35) {
                NSColor(calibratedWhite: 0.85, alpha: 1).setFill()
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 8, height: 8)).fill()
            }
        }
        let text = "Desktop Rug · layer probe\nMouse clicks: \(clickCount)"
        text.draw(at: NSPoint(x: 70, y: 90), withAttributes: [.font: NSFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: NSColor.white])
    }
    override func mouseDown(with event: NSEvent) {
        clickCount += 1
        needsDisplay = true
        ProbeApp.shared.report()
    }
}

final class ProbeApp: NSObject, NSApplicationDelegate {
    static let shared = ProbeApp()
    var panel: ProbePanel!
    var item: NSStatusItem!
    var timer: Timer?
    let view = ProbeView()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let screen = NSScreen.screens.first else { NSApp.terminate(nil); return }
        let frame = NSRect(x: screen.frame.maxX - 530, y: screen.frame.minY + 130, width: 500, height: 330)
        panel = ProbePanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.contentView = view
        panel.orderFrontRegardless()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Rug Probe"
        let menu = NSMenu()
        menu.addItem(withTitle: "Reveal / cover icons", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(withTitle: "Quit probe", action: #selector(quit), keyEquivalent: "q")
        item.menu = menu
        for i in menu.items { i.target = self }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.panel.ignoresMouseEvents = !self.panel.frame.contains(NSEvent.mouseLocation)
        }
        report()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in self.report() }
    }
    @objc func toggle() { panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless(); report() }
    @objc func quit() { NSApp.terminate(nil) }
    func report() {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let all = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        let data: [String: Any] = ["desktopIconLevel": CGWindowLevelForKey(.desktopIconWindow), "rugLevel": panel.level.rawValue, "rugWindow": panel.windowNumber, "visible": panel.isVisible, "clickCount": view.clickCount, "passthrough": panel.ignoresMouseEvents, "screens": NSScreen.screens.map { ["frame": NSStringFromRect($0.frame), "scale": $0.backingScaleFactor] }, "windows": (windows + all.filter { ($0[kCGWindowOwnerName as String] as? String) == "Finder" || ($0[kCGWindowNumber as String] as? Int) == panel.windowNumber }).map { ["owner": $0[kCGWindowOwnerName as String] ?? "", "layer": $0[kCGWindowLayer as String] ?? 0, "id": $0[kCGWindowNumber as String] ?? 0, "bounds": $0[kCGWindowBounds as String] ?? [:]] }]
        if let json = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) {
            try? json.write(to: URL(fileURLWithPath: "/private/tmp/desktop-rug-probe.json"))
        }
    }
}

let app = NSApplication.shared
app.delegate = ProbeApp.shared
app.run()
