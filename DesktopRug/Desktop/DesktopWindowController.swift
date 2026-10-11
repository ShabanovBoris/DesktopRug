import AppKit
import MetalKit

private final class DesktopRugPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class DesktopWindowController {
    let window: NSWindow
    let view: RugMetalView
    let renderer: RugRenderer
    let interaction: RugInteractionController
    private(set) var screen: NSScreen
    private let diagnostic: Bool
    private var sleepObservers: [NSObjectProtocol] = []
    private var displayObserver: NSObjectProtocol?
    var onDisplaysChanged: (() -> Void)?

    init(configuration: RugConfiguration,screen: NSScreen,diagnostic: Bool = false) throws {
        self.screen=screen;self.diagnostic=diagnostic
        let origin=Self.validOrigin(configuration,screen:screen)
        let simulation=ClothSimulation(columns:configuration.quality.columns,rows:configuration.quality.rows,size:SIMD2(configuration.width,configuration.height),origin:origin)
        Self.applyParameters(configuration,to:simulation)
        if diagnostic {
            let frame=NSRect(x:screen.frame.midX-460,y:screen.frame.midY-320,width:920,height:640)
            window=NSWindow(contentRect:frame,styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window.title="Desktop Rug — interaction diagnostics"
            simulation.translate(by:SIMD2(Float(frame.midX)-configuration.width/2,Float(frame.midY)-configuration.height/2)-origin)
        } else {
            let panel=DesktopRugPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            panel.hidesOnDeactivate=false;panel.isFloatingPanel=false
            panel.collectionBehavior=[.canJoinAllSpaces,.stationary,.ignoresCycle,.fullScreenNone]
            // Setting isFloatingPanel resets level, so this must be the final ordering configuration.
            panel.level=NSWindow.Level(rawValue:Int(CGWindowLevelForKey(.desktopIconWindow))+1)
            window=panel
        }
        window.isReleasedWhenClosed=false
        window.acceptsMouseMovedEvents=true
        window.isOpaque=false;window.backgroundColor = .clear;window.hasShadow=false
        window.ignoresMouseEvents = !diagnostic
        view=RugMetalView(frame:NSRect(origin:.zero,size:window.contentLayoutRect.size))
        view.autoresizingMask=[.width,.height]
        window.contentView=view
        renderer=try RugRenderer(view:view,simulation:simulation,configuration:configuration)
        interaction=RugInteractionController(simulation:simulation,view:view)
        interaction.isLocked=configuration.isLocked
        interaction.wake={ [weak self] in self?.wake() }
        renderer.onSettled={ [weak self] in
            self?.view.isPaused=true;self?.view.enableSetNeedsDisplay=true
        }
        renderer.onFrame={ [weak self] in self?.interaction.updatePassthrough() }
        updateScreenOrigin()
        let center=NSWorkspace.shared.notificationCenter
        sleepObservers.append(center.addObserver(forName:NSWorkspace.screensDidSleepNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.view.isPaused=true } })
        sleepObservers.append(center.addObserver(forName:NSWorkspace.screensDidWakeNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.wake() } })
        displayObserver=NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.onDisplaysChanged?() } }
        if configuration.isVisible { show() } else { hide() }
    }

    static func displayID(_ screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static func selectedScreen(_ config: RugConfiguration) -> NSScreen? {
        NSScreen.screens.first(where:{displayID($0)==config.displayID}) ?? NSScreen.screens.first
    }

    static func validOrigin(_ config: RugConfiguration,screen: NSScreen) -> SIMD2<Float> {
        let frame=screen.visibleFrame
        let defaultX=Float(frame.midX)-config.width/2,defaultY=Float(frame.midY)-config.height/2
        let x=config.originX ?? defaultX,y=config.originY ?? defaultY
        return SIMD2(min(max(x,Float(frame.minX)+16),max(Float(frame.minX)+16,Float(frame.maxX)-config.width-16)),min(max(y,Float(frame.minY)+16),max(Float(frame.minY)+16,Float(frame.maxY)-config.height-16)))
    }

    private static func applyParameters(_ config: RugConfiguration,to sim: ClothSimulation) {
        sim.parameters.stiffness=config.stiffness;sim.parameters.bending=config.bending
        sim.parameters.damping=config.damping;sim.parameters.gravity=config.gravity;sim.parameters.iterations=config.quality.iterations
    }

    func update(_ old: RugConfiguration,_ next: RugConfiguration) {
        if old.width != next.width || old.height != next.height || old.quality != next.quality || old.displayID != next.displayID {
            interaction.finishDrag()
            if let selected=Self.selectedScreen(next) { screen=selected }
            if !diagnostic { window.setFrame(screen.frame,display:true) }
            let sim=ClothSimulation(columns:next.quality.columns,rows:next.quality.rows,size:SIMD2(next.width,next.height),origin:Self.validOrigin(next,screen:screen))
            renderer.setSimulation(sim);interaction.simulation=sim
        } else if old.originX != next.originX || old.originY != next.originY {
            let origin=Self.validOrigin(next,screen:screen)
            renderer.simulation.translate(by:origin-renderer.simulation.origin)
        }
        Self.applyParameters(next,to:renderer.simulation)
        renderer.configuration=next;interaction.isLocked=next.isLocked
        if next.isLocked { interaction.finishDrag() }
        view.preferredFramesPerSecond=next.frameRate
        updateScreenOrigin()
        if next.isVisible { show() } else { hide() }
        interaction.updatePassthrough()
    }

    func updateScreenOrigin() {
        let origin=window.convertPoint(toScreen:.zero)
        renderer.screenOrigin=SIMD2(Float(origin.x),Float(origin.y))
    }

    func reconcileScreen(_ nextScreen: NSScreen, configuration: RugConfiguration) {
        interaction.finishDrag()
        screen = nextScreen
        if !diagnostic { window.setFrame(screen.frame, display: true) }
        let origin = Self.validOrigin(configuration, screen: screen)
        renderer.simulation.translate(by: origin - renderer.simulation.origin)
        updateScreenOrigin()
        wake()
    }

    func show() {
        window.orderFrontRegardless();wake()
        if diagnostic { window.makeKeyAndOrderFront(nil) }
    }
    func hide() { interaction.finishDrag();window.orderOut(nil);window.ignoresMouseEvents=true;view.isPaused=true }
    func wake() { if window.isVisible { renderer.wake(view) } }
    func reset() { interaction.finishDrag();renderer.simulation.reset();wake() }
    func setCollisions(_ mounds:[CollisionMound]) { renderer.simulation.setCollisions(mounds);if !renderer.simulation.isSettled { wake() } }

    deinit {
        for observer in sleepObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
    }
}
