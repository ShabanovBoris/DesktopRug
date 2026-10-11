import AppKit
import SwiftUI
import ServiceManagement

@main @MainActor enum DesktopRugApp {
    static func main() {
        if CommandLine.arguments.contains("--finder-status") {
            print("Finder Automation permission status:", FinderDesktopItemProvider.permissionStatus())
            return
        }
        if CommandLine.arguments.contains("--dump-settings") {
            let store=SettingsStore()
            if let data=try? JSONEncoder().encode(store.configuration),let text=String(data:data,encoding:.utf8) { print(text) }
            return
        }
        let app=NSApplication.shared
        let delegate=DesktopRugAppDelegate()
        app.delegate=delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class DesktopRugAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let settings: SettingsStore
    private var desktop: DesktopWindowController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private let finder=FinderDesktopItemProvider()
    private var finderItems: [DesktopItem] = []
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void,Never>?
    private var finderSession=0
    private var finderConnected=false
    private let diagnostic: Bool
    private let validationURL: URL?
    private var finderValidationComplete=false
    private var diagnosticTimer: Timer?
    @Published var loginEnabled=false
    private var visibilityItem: NSMenuItem?
    private var lockItem: NSMenuItem?
    private var loginItem: NSMenuItem?
    private var providerItem: NSMenuItem?

    override init() {
        let args=CommandLine.arguments
        diagnostic=args.contains("--interaction-check")
        if let index=args.firstIndex(of:"--validate"),index+1<args.count { validationURL=URL(fileURLWithPath:args[index+1],isDirectory:true) } else { validationURL=nil }
        if diagnostic || validationURL != nil || args.contains("--validate-ui") {
            let defaults=UserDefaults(suiteName:"dev.desktoprug.validation")!
            defaults.removePersistentDomain(forName:"dev.desktoprug.validation")
            settings=SettingsStore(defaults:defaults)
        } else { settings=SettingsStore() }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let screen=DesktopWindowController.selectedScreen(settings.configuration) else { fail("A graphical macOS desktop is required.");return }
        do {
            let desktop=try DesktopWindowController(configuration:settings.configuration,screen:screen,diagnostic:diagnostic)
            self.desktop=desktop
            desktop.interaction.didMove={ [weak self] origin in self?.settings.update { $0.originX=origin.x;$0.originY=origin.y } }
            desktop.interaction.didTranslate={ [weak self] in self?.updateCollisions() }
            desktop.interaction.addMound={ [weak self] point in self?.addManualMound(at:point) }
            desktop.interaction.reveal={ [weak self] in self?.revealItems() }
            desktop.onDisplaysChanged={ [weak self] in self?.displaysChanged() }
            settings.onChange={ [weak self] old,next in
                guard let self else { return }
                self.desktop?.update(old,next)
                self.updateCollisions()
                if old.finderEnabled != next.finderEnabled && !next.finderEnabled { self.disconnectFinder() }
                if old.isVisible != next.isVisible {
                    if next.isVisible && self.finderConnected { self.startPolling() } else { self.refreshTimer?.invalidate();self.refreshTimer=nil }
                }
                self.updateMenu()
            }
            createMenu()
            if CommandLine.arguments.contains("--settings") { showSettings() }
            loginEnabled=SMAppService.mainApp.status == .enabled
            updateCollisions()
            if settings.configuration.finderEnabled {
                if FinderDesktopItemProvider.permissionStatus() == noErr { connectFinder() }
                else { settings.finderStatus="Finder permission is needed. Click Connect Finder to request it." }
            }
            if diagnostic {
                settings.finderStatus="Interaction diagnostics · deterministic manual mounds"
                let origin=desktop.renderer.simulation.origin
                settings.update { $0.manualMounds=[ManualMound(x:origin.x+330,y:origin.y+210),ManualMound(x:origin.x+350,y:origin.y+205,height:32)] }
                NSApp.activate(ignoringOtherApps:true)
                desktop.window.makeKeyAndOrderFront(nil)
            }
            if diagnostic || CommandLine.arguments.contains("--desktop-input-check") {
                diagnosticTimer=Timer.scheduledTimer(withTimeInterval:0.5,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.writeInteractionDiagnostics() } }
            }
            if let validationURL { Task { await validate(to:validationURL) } }
            if CommandLine.arguments.contains("--connect-finder") { connectFinder() }
            if let index=CommandLine.arguments.firstIndex(of:"--validate-ui"),index+1<CommandLine.arguments.count {
                Task { await validateUI(to:URL(fileURLWithPath:CommandLine.arguments[index+1],isDirectory:true)) }
            }
        } catch { fail(error.localizedDescription) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTask?.cancel();refreshTimer?.invalidate();diagnosticTimer?.invalidate()
        desktop?.hide()
    }

    private func fail(_ message:String) {
        let alert=NSAlert();alert.messageText="Desktop Rug could not start";alert.informativeText=message;alert.runModal()
        NSApp.terminate(nil)
    }

    private func createMenu() {
        let item=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        item.button?.image=NSImage(systemSymbolName:"rectangle.portrait.bottomhalf.inset.filled",accessibilityDescription:"Desktop Rug")
        item.button?.toolTip="Desktop Rug — drag the fabric, lift a corner, right-click to reveal"
        let menu=NSMenu();menu.delegate=self
        let title=NSMenuItem(title:"DESKTOP RUG",action:nil,keyEquivalent:"");title.isEnabled=false;menu.addItem(title)
        visibilityItem=add("Hide Rug",#selector(toggleVisible),to:menu)
        lockItem=add("Lock Rug",#selector(toggleLocked),to:menu)
        add("Reveal Desktop Items",#selector(revealItems),to:menu)
        add("Reset Rug Position",#selector(resetPosition),to:menu)
        menu.addItem(.separator())
        let sizes=NSMenu();for (i,title) in ["Small · 480 × 320","Medium · 640 × 430","Large · 900 × 600"].enumerated() { let choice=add(title,#selector(changeSize(_:)),to:sizes);choice.tag=i }
        let sizeItem=NSMenuItem(title:"Rug Size",action:nil,keyEquivalent:"");sizeItem.submenu=sizes;menu.addItem(sizeItem)
        let qualities=NSMenu();for (i,quality) in PhysicsQuality.allCases.enumerated() { let choice=add(quality.title,#selector(changeQuality(_:)),to:qualities);choice.tag=i }
        let qualityItem=NSMenuItem(title:"Physics Quality",action:nil,keyEquivalent:"");qualityItem.submenu=qualities;menu.addItem(qualityItem)
        loginItem=add("Start at Login",#selector(toggleLogin),to:menu)
        menu.addItem(.separator())
        providerItem=NSMenuItem(title:"Manual mounds · Finder not connected",action:nil,keyEquivalent:"");providerItem?.isEnabled=false;menu.addItem(providerItem!)
        add("Connect Finder…",#selector(connectFinder),to:menu)
        add("Add Manual Mound",#selector(addMoundAtCenter),to:menu)
        menu.addItem(.separator())
        add("Settings…",#selector(showSettings),to:menu,key:",")
        add("Quit Desktop Rug",#selector(quit),to:menu,key:"q")
        item.menu=menu;statusItem=item;updateMenu()
        let mainMenu=NSMenu()
        let applicationItem=NSMenuItem()
        mainMenu.addItem(applicationItem)
        let applicationMenu=NSMenu()
        add("Settings…",#selector(showSettings),to:applicationMenu,key:",")
        applicationMenu.addItem(.separator())
        add("Quit Desktop Rug",#selector(quit),to:applicationMenu,key:"q")
        applicationItem.submenu=applicationMenu
        NSApp.mainMenu=mainMenu
    }

    @discardableResult private func add(_ title:String,_ action:Selector,to menu:NSMenu,key:String="") -> NSMenuItem {
        let item=NSMenuItem(title:title,action:action,keyEquivalent:key);item.target=self;menu.addItem(item);return item
    }

    func menuWillOpen(_ menu:NSMenu) { updateMenu() }
    private func updateMenu() {
        let config=settings.configuration
        visibilityItem?.title=config.isVisible ? "Hide Rug" : "Show Rug"
        lockItem?.title=config.isLocked ? "Unlock Rug" : "Lock Rug"
        loginItem?.state=SMAppService.mainApp.status == .enabled ? .on : .off
        providerItem?.title=finderConnected ? "Finder · \(finderItems.count) positioned items" : "Manual mounds · Finder not connected"
    }

    @objc func toggleVisible() { settings.update { $0.isVisible.toggle() } }
    @objc func toggleLocked() { settings.update { $0.isLocked.toggle() } }
    @objc func revealItems() { settings.update { $0.isVisible=false } }
    @objc func resetPosition() {
        settings.update { $0.originX=nil;$0.originY=nil;$0.isVisible=true }
        if let desktop {
            let target=DesktopWindowController.validOrigin(settings.configuration,screen:desktop.screen)
            desktop.renderer.simulation.translate(by:target-desktop.renderer.simulation.origin)
            desktop.reset()
        }
    }
    @objc private func changeSize(_ item:NSMenuItem) {
        let sizes:[SIMD2<Float>]=[SIMD2(480,320),SIMD2(640,430),SIMD2(900,600)]
        let size=sizes[item.tag];settings.update { $0.width=size.x;$0.height=size.y }
    }
    @objc private func changeQuality(_ item:NSMenuItem) { settings.update { $0.quality=PhysicsQuality.allCases[item.tag] } }
    @objc func toggleLogin() { setStartAtLogin(SMAppService.mainApp.status != .enabled) }
    func setStartAtLogin(_ enabled:Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled=SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval { settings.runtimeStatus="Approve Desktop Rug in System Settings → General → Login Items." }
        } catch { settings.runtimeStatus="Start at Login: \(error.localizedDescription)" }
        updateMenu()
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let root=SettingsView(store:settings,app:self)
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:680,height:650),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
            window.title="Desktop Rug";window.isReleasedWhenClosed=false
            window.appearance=NSAppearance(named:.aqua)
            window.contentView=NSHostingView(rootView:root);window.center()
            settingsWindow=window
        }
        NSApp.activate(ignoringOtherApps:true);settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc func connectFinder() {
        guard refreshTask == nil else { return }
        settings.update { $0.finderEnabled=true }
        settings.finderStatus="Reading Finder positions…"
        refreshFinder(requestPermission:true)
    }

    func disconnectFinder() {
        finderSession += 1;refreshTask?.cancel();refreshTask=nil
        refreshTimer?.invalidate();refreshTimer=nil;finderConnected=false;finderItems=[]
        settings.finderStatus="Finder is disconnected. Manual mounds remain available."
        if settings.configuration.finderEnabled { settings.update { $0.finderEnabled=false } }
        updateCollisions();updateMenu()
    }

    private func startPolling() {
        refreshTimer?.invalidate()
        guard finderConnected && settings.configuration.isVisible else { refreshTimer=nil;return }
        refreshTimer=Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.refreshFinder(requestPermission:false) } }
    }

    private func refreshFinder(requestPermission:Bool) {
        guard refreshTask == nil && settings.configuration.finderEnabled else { return }
        if !requestPermission && FinderDesktopItemProvider.permissionStatus() != noErr {
            settings.finderStatus="Finder permission is unavailable. Reconnect Finder or use manual mounds."
            finderConnected=false;finderItems=[];refreshTimer?.invalidate();refreshTimer=nil;updateCollisions();updateMenu();return
        }
        let session=finderSession
        refreshTask=Task { [weak self] in
            guard let self else { return }
            defer { if session==self.finderSession { self.refreshTask=nil } }
            do {
                if requestPermission { try await self.finder.requestPermission() }
                guard !Task.isCancelled && session==self.finderSession else { return }
                let snapshot=try await self.finder.fetchItems()
                guard !Task.isCancelled && session==self.finderSession && self.settings.configuration.finderEnabled else { return }
                self.finderItems=snapshot.items;self.finderConnected=true
                var status="Finder connected · \(snapshot.items.count) positioned items. Automatic collision is supported on the main display; Stacks may report stale positions."
                if snapshot.skippedPositions>0 { status += " \(snapshot.skippedPositions) unplaced items were skipped." }
                if self.settings.finderStatus != status { self.settings.finderStatus=status }
                self.updateCollisions();self.updateMenu()
                if CommandLine.arguments.contains("--validate-finder") && !self.finderValidationComplete {
                    self.finderValidationComplete=true
                    try self.validateFinder(snapshot)
                }
                if self.refreshTimer == nil { self.startPolling() }
            } catch is CancellationError { }
            catch {
                guard session==self.finderSession else { return }
                self.finderItems=[];self.finderConnected=false;self.refreshTimer?.invalidate();self.refreshTimer=nil
                self.settings.finderStatus=error.localizedDescription;self.updateCollisions();self.updateMenu()
                if let index=CommandLine.arguments.firstIndex(of:"--validate-finder"),index+1<CommandLine.arguments.count {
                    let directory=URL(fileURLWithPath:CommandLine.arguments[index+1],isDirectory:true)
                    let report:[String:Any]=["finderGeometryVerified":false,"permissionStatus":FinderDesktopItemProvider.permissionStatus(),"error":error.localizedDescription,"usesMockItems":false]
                    if let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:directory.appendingPathComponent("finder-integration.json")) }
                }
            }
        }
    }

    private func updateCollisions() {
        guard let desktop else { return }
        var mounds=settings.configuration.manualMounds.map(\.collision)
        if finderConnected, let main=NSScreen.screens.first,DesktopWindowController.displayID(desktop.screen)==DesktopWindowController.displayID(main) {
            let height=Float(main.frame.maxY),width=Float(main.frame.width)
            mounds += finderItems.filter { $0.finderPosition.x>0 && $0.finderPosition.x<width && $0.finderPosition.y>0 && $0.finderPosition.y<Float(main.frame.height) }.map { $0.collision(mainDisplayHeight:height) }
        }
        let sim=desktop.renderer.simulation
        let lower=sim.origin-SIMD2(repeating:180),upper=sim.origin+sim.size+SIMD2(repeating:180)
        mounds=mounds.filter { $0.center.x+$0.halfExtent.x>lower.x && $0.center.x-$0.halfExtent.x<upper.x && $0.center.y+$0.halfExtent.y>lower.y && $0.center.y-$0.halfExtent.y<upper.y }
        desktop.setCollisions(mounds)
    }

    @objc func addMoundAtCenter() {
        guard let sim=desktop?.renderer.simulation else { return }
        addManualMound(at:sim.origin+sim.size/2)
    }
    func addManualMound(at point:SIMD2<Float>) { settings.update { if $0.manualMounds.count<64 { $0.manualMounds.append(ManualMound(x:point.x,y:point.y)) } } }
    func clearManualMounds() { settings.update { $0.manualMounds=[] } }
    func relaxFabric() { desktop?.reset() }

    private func displaysChanged() {
        guard !diagnostic,let desktop,let screen=DesktopWindowController.selectedScreen(settings.configuration) else { return }
        let id=DesktopWindowController.displayID(screen)
        // AppKit also emits this notification without a display or frame change; those events must preserve the saved position.
        guard DesktopWindowController.displayID(desktop.screen) != id || desktop.window.frame != screen.frame else { return }
        desktop.interaction.finishDrag()
        var config=settings.configuration;config.displayID=id
        let origin=DesktopWindowController.validOrigin(config,screen:screen)
        config.originX=origin.x;config.originY=origin.y
        desktop.reconcileScreen(screen,configuration:config)
        settings.update { $0=config }
        updateCollisions()
    }

    private func writeInteractionDiagnostics() {
        guard let desktop else { return }
        let sim=desktop.renderer.simulation
        var data:[String:Any]=["mouseDowns":desktop.interaction.mouseDownCount,"cornerDrags":desktop.interaction.cornerDragCount,"grabbed":sim.grabbedIndex as Any? ?? NSNull(),"maxHeight":sim.positions.map(\.z).max() ?? 0,"settled":sim.isSettled,"recoveries":sim.recoveryCount,"frameCount":desktop.renderer.frameCount,"fps":desktop.renderer.actualFPS,"physicsMS":desktop.renderer.physicsMilliseconds,"gpuMS":desktop.renderer.gpuMilliseconds,"origin":[sim.origin.x,sim.origin.y],"screenOrigin":[desktop.renderer.screenOrigin.x,desktop.renderer.screenOrigin.y],"corners":sim.cornerIndices.map { let p=ClothGeometry.project(sim.positions[$0]);return [p.x,p.y] },"passthrough":desktop.window.ignoresMouseEvents]
        data["diagnosticWindow"]=diagnostic
        data["finderConnected"]=finderConnected
        data["finderItemCount"]=finderItems.count
        data["selfContacts"]=sim.selfContactCount
        data["edgeSelfContacts"]=sim.edgeSelfContactCount
        data["windowLevel"]=desktop.window.level.rawValue
        if let configuration=try? JSONEncoder().encode(settings.configuration) {
            data["configuration"]=try? JSONSerialization.jsonObject(with:configuration)
        }
        if let json=try? JSONSerialization.data(withJSONObject:data,options:[.prettyPrinted,.sortedKeys]) { try? json.write(to:URL(fileURLWithPath:"/private/tmp/desktop-rug-interaction.json")) }
    }

    private func validateFinder(_ snapshot:DesktopItemSnapshot) throws {
        guard let desktop,let main=NSScreen.screens.first,let index=CommandLine.arguments.firstIndex(of:"--validate-finder"),index+1<CommandLine.arguments.count else { return }
        let directory=URL(fileURLWithPath:CommandLine.arguments[index+1],isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let mainItems=snapshot.items.filter { $0.finderPosition.x>0 && $0.finderPosition.x<Float(main.frame.width) && $0.finderPosition.y>0 && $0.finderPosition.y<Float(main.frame.height) }
        var report:[String:Any]=["permissionStatus":FinderDesktopItemProvider.permissionStatus(),"finderItemCount":snapshot.items.count,"mainDisplayItems":mainItems.count,"skippedPositions":snapshot.skippedPositions,"arrangement":snapshot.arrangement,"usesMockItems":false,"movesDesktopFiles":false]
        report["finderDesktopDirectory"]=snapshot.desktopDirectory?.path ?? "unavailable"
        if let item=mainItems.first {
            let point=ClothGeometry.finderPoint(x:item.finderPosition.x,y:item.finderPosition.y,mainDisplayHeight:Float(main.frame.maxY))
            settings.update { $0.displayID=DesktopWindowController.displayID(main);$0.originX=point.x-$0.width/2;$0.originY=point.y-$0.height/2;$0.isVisible=true }
            updateCollisions()
            let sim=desktop.renderer.simulation
            for _ in 0..<1200 { sim.step() }
            try desktop.renderer.capture(to:directory.appendingPathComponent("05-real-finder-items.png"))
            report["realCollisionVolumes"]=sim.collisions.mounds.count
            report["maxHeight"]=sim.positions.map(\.z).max() ?? 0
            report["targetIconInsideRenderedRug"]=ClothGeometry.hitVertex(at:point,positions:sim.positions,indices:sim.indices) != nil
            report["recoveries"]=sim.recoveryCount
            report["settled"]=sim.isSettled
            report["finderGeometryVerified"] = !sim.collisions.mounds.isEmpty && (sim.positions.map(\.z).max() ?? 0)>10
        } else { report["finderGeometryVerified"]=false;report["limitation"]="Finder returned no placed icons on the main display." }
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("finder-integration.json"))
    }

    private func validateUI(to directory:URL) async {
        var report:[String:Any]=[:]
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            showSettings()
            for (tab,name) in ["appearance","physics","desktop"].enumerated() {
                guard let window=settingsWindow else { break }
                window.contentView=NSHostingView(rootView:SettingsView(store:settings,app:self,initialTab:tab))
                window.contentView?.layoutSubtreeIfNeeded()
                try await Task.sleep(nanoseconds:250_000_000)
                guard let view=window.contentView,let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else { throw RugRendererError.unavailable("Could not capture the native Settings view.") }
                view.cacheDisplay(in:view.bounds,to:bitmap)
                guard let png=bitmap.representation(using:.png,properties:[:]) else { throw RugRendererError.unavailable("Could not encode Settings capture.") }
                try png.write(to:directory.appendingPathComponent("settings-\(name).png"))
            }
            guard let desktop else { throw RugRendererError.unavailable("No desktop window") }
            let prior=settings.configuration
            let sim=desktop.renderer.simulation
            let defaults=UserDefaults(suiteName:"dev.desktoprug.validation")!
            var textureResults:[[String:Any]]=[]
            for texture in RugTexture.allCases {
                guard let image=NSImage(named:NSImage.Name(texture.rawValue)) else { throw RugRendererError.unavailable("The \(texture.title) preview is missing.") }
                let positions=sim.positions
                settings.update { $0.texture=texture }
                let preservesGeometry=sim.positions==positions
                let roundTrip=SettingsStore(defaults:defaults).configuration==settings.configuration
                guard preservesGeometry && roundTrip else { throw RugRendererError.unavailable("Texture selection changed geometry or did not persist.") }
                try desktop.renderer.capture(to:directory.appendingPathComponent("texture-\(texture.rawValue)-flat.png"))
                textureResults.append(["texture":texture.rawValue,"title":texture.title,"previewSize":NSStringFromSize(image.size),"settingsRoundTrip":roundTrip,"selectionPreservesGeometry":preservesGeometry])
            }
            let corner=sim.cornerIndices.last!
            sim.grab(index:corner);sim.moveGrab(to:sim.positions[corner]+SIMD3(-180,-90,150))
            for _ in 0..<180 { sim.step() }
            for texture in RugTexture.allCases {
                settings.update { $0.texture=texture }
                try desktop.renderer.capture(to:directory.appendingPathComponent("texture-\(texture.rawValue)-folded.png"))
            }
            sim.releaseGrab();sim.reset()
            settings.update { $0=prior }
            report["textureChecks"]=textureResults
            report["allTexturesRenderedFlatAndFolded"]=true
            settings.update { $0.isVisible=true;$0.isLocked=false }
            report["showRug"]=desktop.window.isVisible
            revealItems()
            report["revealRemovesWindow"] = !desktop.window.isVisible && desktop.window.ignoresMouseEvents
            toggleVisible();toggleLocked()
            report["lockPassesMouseThrough"]=desktop.window.isVisible && desktop.window.ignoresMouseEvents
            settings.update { $0.originX=Float(desktop.screen.visibleFrame.minX)+80;$0.originY=Float(desktop.screen.visibleFrame.minY)+80 }
            let positioned=settings.configuration,position=desktop.renderer.simulation.origin
            displaysChanged()
            report["unchangedDisplayPreservesSavedPosition"] = settings.configuration==positioned && desktop.renderer.simulation.origin==position
            var displayResults:[[String:Any]]=[]
            for screen in NSScreen.screens {
                let id=DesktopWindowController.displayID(screen)
                settings.update { $0.displayID=id;$0.originX=nil;$0.originY=nil;$0.isLocked=false }
                try await Task.sleep(nanoseconds:100_000_000)
                displayResults.append(["requestedDisplay":id,"actualDisplay":desktop.window.screen.map(DesktopWindowController.displayID) ?? 0,"windowScale":desktop.window.backingScaleFactor,"expectedScale":screen.backingScaleFactor,"frame":NSStringFromRect(desktop.window.frame)])
            }
            report["displayChecks"]=displayResults
            settings.update { $0=prior }
            report["nativeSettingsViewsRendered"]=true
            report["mainMenuAvailable"]=NSApp.mainMenu != nil
            report["success"]=true
        } catch { report["error"]=error.localizedDescription;report["success"]=false }
        if let json=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) { try? json.write(to:directory.appendingPathComponent("native-ui-validation.json")) }
        if !CommandLine.arguments.contains("--connect-finder") { NSApp.terminate(nil) }
    }

    private func validate(to directory:URL) async {
        guard let desktop else { return }
        var report:[String:Any]=["date":"2026-10-10","mode":"native desktop window; explicit deterministic test collisions","finderAutomaticDetectionVerified":false]
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let sim=desktop.renderer.simulation
            try desktop.renderer.capture(to:directory.appendingPathComponent("00-flat.png"))
            let center=sim.origin+sim.size/2
            guard let main=NSScreen.screens.first else { throw DesktopProviderError.unavailable("No main display") }
            let fake=DesktopItem(name:"Deterministic test item",url:URL(fileURLWithPath:"/not-a-real-desktop-item"),finderPosition:SIMD2(center.x,Float(main.frame.maxY)-center.y),iconSize:64)
            let snapshot=try await MockDesktopItemProvider(items:[fake]).fetchItems()
            sim.setCollisions(snapshot.items.map { $0.collision(mainDisplayHeight:Float(main.frame.maxY)) })
            for _ in 0..<900 { sim.step() }
            let singleHeight=sim.positions.map(\.z).max() ?? 0
            try desktop.renderer.capture(to:directory.appendingPathComponent("01-single-object.png"))
            sim.setCollisions([fake.collision(mainDisplayHeight:Float(main.frame.maxY)),CollisionMound(center:center+SIMD2(12,6),halfExtent:SIMD2(55,48),height:35)])
            for _ in 0..<900 { sim.step() }
            let pileHeight=sim.positions.map(\.z).max() ?? 0
            try desktop.renderer.capture(to:directory.appendingPathComponent("02-overlapping-objects.png"))
            let corner=sim.cornerIndices.last!,p=sim.positions[corner]
            sim.grab(index:corner);sim.moveGrab(to:p+SIMD3(-220,-110,170))
            for _ in 0..<240 { sim.step() }
            try desktop.renderer.capture(to:directory.appendingPathComponent("03-lifted-corner.png"))
            sim.releaseGrab()
            for _ in 0..<2400 { sim.step() }
            try desktop.renderer.capture(to:directory.appendingPathComponent("04-released.png"))
            report["singleObjectMaxHeight"]=singleHeight;report["overlapMaxHeight"]=pileHeight
            report["sleepAfterRelease"]=sim.isSettled;report["maximumStretchRatio"]=sim.maximumStretchRatio();report["physicsRecoveries"]=sim.recoveryCount
            report["finitePositions"]=sim.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }
            let testDefaults=UserDefaults(suiteName:"dev.desktoprug.persistence-check")!
            testDefaults.removePersistentDomain(forName:"dev.desktoprug.persistence-check")
            let store=SettingsStore(defaults:testDefaults)
            store.update { $0.texture = .indigo;$0.originX = -80;$0.originY=1600;$0.damping=0.22 }
            report["settingsRoundTrip"]=SettingsStore(defaults:testDefaults).configuration==store.configuration
            testDefaults.removePersistentDomain(forName:"dev.desktoprug.persistence-check")
            let windows=CGWindowListCopyWindowInfo(.optionAll,kCGNullWindowID) as? [[String:Any]] ?? []
            report["windowLevels"]=windows.filter { ($0[kCGWindowNumber as String] as? Int)==desktop.window.windowNumber || (($0[kCGWindowOwnerName as String] as? String)=="Finder" && ($0[kCGWindowLayer as String] as? Int)==Int(CGWindowLevelForKey(.desktopIconWindow))) }.map { ["owner":$0[kCGWindowOwnerName as String] ?? "","layer":$0[kCGWindowLayer as String] ?? 0] }
            report["screens"]=NSScreen.screens.map { ["id":DesktopWindowController.displayID($0),"scale":$0.backingScaleFactor,"frame":NSStringFromRect($0.frame)] as [String:Any] }
            sim.grab(index:corner);sim.moveGrab(to:sim.positions[corner]+SIMD3(-80,0,100));desktop.wake()
            let firstFrame=desktop.renderer.frameCount
            try await Task.sleep(nanoseconds:3_000_000_000)
            report["framesInThreeSeconds"]=desktop.renderer.frameCount-firstFrame
            report["observedFPS"]=desktop.renderer.actualFPS
            report["lastPhysicsMS"]=desktop.renderer.physicsMilliseconds;report["lastGPUms"]=desktop.renderer.gpuMilliseconds
            report["lastFrameCPUms"]=desktop.renderer.frameMilliseconds;report["droppedGPUframes"]=desktop.renderer.droppedFrames
            sim.releaseGrab();desktop.wake()
            if CommandLine.arguments.contains("--deep-fold") {
                sim.reset()
                let start=sim.positions[corner]
                sim.grab(index:corner)
                sim.moveGrab(to:start+SIMD3(-sim.size.x*0.78,-sim.size.y*0.70,200))
                var peakContacts=0,peakEdgeContacts=0
                for _ in 0..<300 { sim.step();peakContacts=max(peakContacts,sim.selfContactCount);peakEdgeContacts=max(peakEdgeContacts,sim.edgeSelfContactCount) }
                try desktop.renderer.capture(to:directory.appendingPathComponent("06-deep-fold.png"))
                report["deepFoldPeakSelfContacts"]=peakContacts
                report["deepFoldPeakEdgeContacts"]=peakEdgeContacts
                report["deepFoldStretchRatio"]=sim.maximumStretchRatio()
                sim.releaseGrab()
                for _ in 0..<2400 { sim.step() }
                try desktop.renderer.capture(to:directory.appendingPathComponent("07-deep-fold-released.png"))
                report["deepFoldSettled"]=sim.isSettled
                report["deepFoldRecoveries"]=sim.recoveryCount
            }
            report["metalCaptureVerified"]=true
            report["desktopMouseInteractionVerified"]=false
            report["success"]=singleHeight>20 && pileHeight>singleHeight+10 && sim.recoveryCount==0
        } catch { report["success"]=false;report["error"]=error.localizedDescription }
        if let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:directory.appendingPathComponent("native-validation.json")) }
        NSApp.terminate(nil)
    }
}
