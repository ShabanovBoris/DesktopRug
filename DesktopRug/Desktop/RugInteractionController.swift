import AppKit
import MetalKit
import simd

@MainActor final class RugMetalView: MTKView {
    weak var interaction: RugInteractionController?
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { interaction?.mouseDown(event) }
    override func mouseDragged(with event: NSEvent) { interaction?.mouseDragged(event) }
    override func mouseUp(with event: NSEvent) { interaction?.mouseUp(event) }
    override func mouseMoved(with event: NSEvent) {
        guard let interaction, !interaction.isLocked else { return }
        if interaction.contains(interaction.point(for:event)) { NSCursor.openHand.set() }
        else { NSCursor.arrow.set() }
    }
    override func rightMouseDown(with event: NSEvent) { interaction?.reveal?() }
}

@MainActor final class RugInteractionController {
    enum Drag {
        case corner(index: Int, startPointer: SIMD2<Float>, startHeight: Float)
        case rug(lastPointer: SIMD2<Float>)
    }
    var simulation: ClothSimulation
    weak var view: RugMetalView?
    var isLocked = false
    private(set) var drag: Drag?
    private(set) var mouseDownCount = 0
    private(set) var cornerDragCount = 0
    var wake: (() -> Void)?
    var didMove: ((SIMD2<Float>) -> Void)?
    var didTranslate: (() -> Void)?
    var addMound: ((SIMD2<Float>) -> Void)?
    var reveal: (() -> Void)?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(simulation: ClothSimulation, view: RugMetalView) {
        self.simulation = simulation; self.view = view
        view.interaction = self
        // Mouse-only monitors do not require Accessibility; ignored pixels must remain available to Finder.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseUp, .otherMouseUp]) { [weak self] event in
            guard let self else { return }
            if event.type == .leftMouseUp && self.drag != nil { self.finishDrag() }
            self.updatePassthrough()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseUp]) { [weak self] event in
            self?.updatePassthrough(); return event
        }
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }

    func point(for event: NSEvent) -> SIMD2<Float> {
        guard let window = view?.window else { return .zero }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        return SIMD2(Float(point.x),Float(point.y))
    }

    func contains(_ point: SIMD2<Float>) -> Bool {
        for index in simulation.cornerIndices where simd_distance(ClothGeometry.project(simulation.positions[index]),point) < 20 { return true }
        return ClothGeometry.hitVertex(at: point,positions: simulation.positions,indices: simulation.indices) != nil
    }

    func updatePassthrough() {
        guard let window = view?.window else { return }
        let p=NSEvent.mouseLocation,point=SIMD2(Float(p.x),Float(p.y))
        let over=window.isVisible && !isLocked && (drag != nil || contains(point))
        window.ignoresMouseEvents = !over
    }

    func mouseDown(_ event: NSEvent) {
        guard !isLocked else { return }
        let pointer=point(for:event)
        guard contains(pointer) else { return }
        mouseDownCount += 1
        if event.modifierFlags.contains(.shift) { addMound?(pointer);return }
        var corner: Int?
        var best: Float=28
        for index in simulation.cornerIndices {
            let d=simd_distance(ClothGeometry.project(simulation.positions[index]),pointer)
            if d<best { corner=index;best=d }
        }
        if event.modifierFlags.contains(.option) { corner=ClothGeometry.hitVertex(at:pointer,positions:simulation.positions,indices:simulation.indices) }
        if let corner {
            simulation.grab(index:corner)
            drag = .corner(index:corner,startPointer:pointer,startHeight:simulation.positions[corner].z)
            cornerDragCount += 1
            NSCursor.closedHand.set()
        } else { drag = .rug(lastPointer:pointer);NSCursor.closedHand.set() }
        wake?();updatePassthrough()
    }

    func mouseDragged(_ event: NSEvent) {
        guard let drag else { return }
        let pointer=point(for:event)
        switch drag {
        case .corner(_,let start,let height):
            let lift=min(260,max(18,height+simd_distance(start,pointer)*0.65))
            let xy=pointer-ClothGeometry.liftProjection*lift
            simulation.moveGrab(to:SIMD3(xy.x,xy.y,lift))
        case .rug(let last):
            simulation.translate(by:pointer-last)
            self.drag = .rug(lastPointer:pointer)
            didTranslate?()
        }
        wake?()
    }

    func mouseUp(_ event: NSEvent) { finishDrag() }
    func finishDrag() {
        guard drag != nil else { return }
        simulation.releaseGrab();drag=nil
        didMove?(simulation.origin)
        wake?();updatePassthrough();NSCursor.arrow.set()
    }
}
