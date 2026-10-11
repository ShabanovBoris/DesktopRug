import AppKit
import MetalKit
import simd

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
        let simulation=ClothSimulation(columns:configuration.quality.columns,rows:configuration.quality.rows,size:SIMD2(configuration.width,configuration.height),origin:origin,rotationDegrees:configuration.rotationDegrees)
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
        let size=SIMD2(config.width,config.height)
        let extent=ClothGeometry.rotatedHalfExtent(size:size,degrees:config.rotationDegrees)
        let center=SIMD2((config.originX ?? (Float(frame.midX)-size.x/2))+size.x/2,(config.originY ?? (Float(frame.midY)-size.y/2))+size.y/2)
        let lower=SIMD2(Float(frame.minX)+16,Float(frame.minY)+16)+extent
        let upper=SIMD2(Float(frame.maxX)-16,Float(frame.maxY)-16)-extent
        return simd_min(simd_max(center,lower),simd_max(lower,upper))-size/2
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
            let sim=ClothSimulation(columns:next.quality.columns,rows:next.quality.rows,size:SIMD2(next.width,next.height),origin:Self.validOrigin(next,screen:screen),rotationDegrees:next.rotationDegrees)
            renderer.setSimulation(sim);interaction.simulation=sim
        } else if old.originX != next.originX || old.originY != next.originY || old.rotationDegrees != next.rotationDegrees {
            renderer.simulation.setRotation(degrees:next.rotationDegrees)
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
