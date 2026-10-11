import SwiftUI
import ServiceManagement

@MainActor struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    let app: DesktopRugAppDelegate
    @State private var tab = 0
    @State private var loginEnabled = false
    private let accent = Color(red:0.63,green:0.27,blue:0.21)

    init(store:SettingsStore,app:DesktopRugAppDelegate,initialTab:Int=0) {
        self.store=store;self.app=app;_tab=State(initialValue:initialTab)
    }

    private func binding<Value>(_ path: WritableKeyPath<RugConfiguration,Value>) -> Binding<Value> {
        Binding(get:{store.configuration[keyPath:path]},set:{value in store.update {$0[keyPath:path]=value}})
    }

    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:24) {
                ZStack {
                    RoundedRectangle(cornerRadius:14).fill(Color.primary.opacity(0.04))
                    if let image=NSImage(named:NSImage.Name(store.configuration.texture.rawValue)) {
                        Image(nsImage:image).resizable().aspectRatio(contentMode:.fit).padding(13).rotationEffect(.degrees(-5)).shadow(color:.black.opacity(0.22),radius:6,x:0,y:5)
                    }
                }.frame(width:166,height:118)
                VStack(alignment:.leading,spacing:7) {
                    Text("Desktop Rug").font(.system(size:28,weight:.semibold,design:.serif))
                    Text("A little order. A lot of texture.").font(.system(size:13)).foregroundStyle(.secondary)
                    HStack(spacing:6) {
                        Circle().fill(store.configuration.isVisible ? Color.green : Color.secondary).frame(width:6,height:6)
                        Text(store.configuration.isVisible ? "On your desktop" : "Desktop items revealed").font(.system(size:11,weight:.medium))
                    }.padding(.top,7)
                }
                Spacer(minLength:0)
            }.padding(24)
            Divider()
            Picker("Settings section",selection:$tab) {
                Text("Appearance").tag(0);Text("Cloth & Motion").tag(1);Text("Desktop").tag(2)
            }.pickerStyle(.segmented).padding(.horizontal,24).padding(.top,18)
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    if tab==0 { appearance }
                    else if tab==1 { physics }
                    else { desktop }
                    if let error=store.persistenceError { Text(error).font(.caption).foregroundStyle(.red) }
                    if store.runtimeStatus != "Ready" { Text(store.runtimeStatus).font(.caption).foregroundStyle(.secondary) }
                }.padding(24)
            }.frame(maxHeight:.infinity)
            Divider()
            HStack {
                Text("Drag to move · Lift a corner · Right-click to reveal").font(.system(size:10)).foregroundStyle(.secondary)
                Spacer()
                Button(store.configuration.isVisible ? "Reveal Items" : "Show Rug") { app.toggleVisible() }
                    .buttonStyle(.borderedProminent).tint(accent)
            }.padding(18)
        }.frame(width:680,height:650)
            .background(Color(red:0.97,green:0.96,blue:0.94))
            .preferredColorScheme(.light)
            .tint(accent)
        .onAppear { loginEnabled=SMAppService.mainApp.status == .enabled }
    }

    private var appearance: some View {
        VStack(alignment:.leading,spacing:18) {
            Text("Woven for your workspace").font(.headline)
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:14) {
                ForEach(RugTexture.allCases,id:\.self) { texture in
                    Button { store.update {$0.texture=texture} } label: {
                        VStack(alignment:.leading,spacing:9) {
                            if let image=NSImage(named:NSImage.Name(texture.rawValue)) {
                                Image(nsImage:image).resizable().aspectRatio(contentMode:.fit).frame(maxWidth:.infinity).frame(height:100).clipShape(RoundedRectangle(cornerRadius:4))
                            }
                            HStack {
                                Text(texture.title).font(.system(size:12,weight:.medium))
                                Spacer()
                                Image(systemName:store.configuration.texture==texture ? "checkmark.circle.fill" : "circle").foregroundStyle(store.configuration.texture==texture ? accent : Color.secondary)
                            }
                        }.padding(10).background(RoundedRectangle(cornerRadius:9).fill(Color.primary.opacity(0.035)))
                            .overlay(RoundedRectangle(cornerRadius:9).stroke(store.configuration.texture==texture ? accent : Color.primary.opacity(0.10),lineWidth:store.configuration.texture==texture ? 2 : 1))
                    }.buttonStyle(.plain).accessibilityLabel(texture.title)
                }
            }
            GroupBox("Dimensions") {
                VStack(spacing:14) {
                    slider("Width",value:binding(\.width),range:280...1400,format:"%.0f pt")
                    slider("Height",value:binding(\.height),range:200...950,format:"%.0f pt")
                }.padding(10)
            }
            HStack {
                Toggle("Lock rug in place",isOn:binding(\.isLocked))
                Spacer()
                Button("Reset Position") { app.resetPosition() }
            }
        }
    }

    private var physics: some View {
        VStack(alignment:.leading,spacing:18) {
            Text("A fabric that responds").font(.headline)
            GroupBox("Material") {
                VStack(spacing:16) {
                    slider("Stretch stiffness",value:binding(\.stiffness),range:0.4...1,format:"%.2f")
                    slider("Bending resistance",value:binding(\.bending),range:0.05...1,format:"%.2f")
                    slider("Damping",value:binding(\.damping),range:0.02...0.8,format:"%.2f")
                }.padding(10)
            }
            GroupBox("Performance") {
                VStack(alignment:.leading,spacing:15) {
                    Picker("Physics quality",selection:binding(\.quality)) {
                        ForEach(PhysicsQuality.allCases,id:\.self) { Text($0.title).tag($0) }
                    }
                    Picker("Frame-rate limit",selection:binding(\.frameRate)) {
                        Text("30 fps").tag(30);Text("60 fps").tag(60);Text("120 fps").tag(120)
                    }
                    Toggle("Soft contact shadows",isOn:binding(\.highQualityShadows))
                    Text("Animation pauses when the cloth settles. Balanced uses \(PhysicsQuality.balanced.columns) × \(PhysicsQuality.balanced.rows) particles.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(10)
            }
            HStack { Button("Relax Fabric") { app.relaxFabric() };Spacer();Toggle("Show collision outlines",isOn:binding(\.debugCollisions)) }
            Text("Option-drag to grab any point. Shift-click to place a manual mound.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var desktop: some View {
        VStack(alignment:.leading,spacing:17) {
            GroupBox("Display") {
                VStack(alignment:.leading,spacing:10) {
                    Picker("Place rug on",selection:Binding(get:{store.configuration.displayID ?? NSScreen.screens.first.map(DesktopWindowController.displayID) ?? 0},set:{id in store.update {$0.displayID=id;$0.originX=nil;$0.originY=nil}})) {
                        ForEach(NSScreen.screens,id:\.localizedName) { screen in Text(screen.localizedName).tag(DesktopWindowController.displayID(screen)) }
                    }
                    Toggle("Start at Login",isOn:Binding(get:{loginEnabled},set:{value in app.setStartAtLogin(value);loginEnabled=SMAppService.mainApp.status == .enabled}))
                }.padding(10)
            }
            GroupBox("Finder icons") {
                VStack(alignment:.leading,spacing:12) {
                    Text(store.finderStatus).font(.system(size:11)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    HStack {
                        Button(store.configuration.finderEnabled ? "Reconnect Finder…" : "Connect Finder…") { app.connectFinder() }
                        if store.configuration.finderEnabled { Button("Disconnect") { app.disconnectFinder() } }
                    }
                    Text("Automation access reads icon positions. Your files are never moved, changed or deleted.").font(.caption2).foregroundStyle(.secondary)
                }.padding(10)
            }
            GroupBox("Manual collision mounds") {
                VStack(alignment:.leading,spacing:11) {
                    HStack {
                        Text("\(store.configuration.manualMounds.count) manually placed objects").font(.caption).foregroundStyle(.secondary)
                        Spacer();Button("Add Mound") { app.addMoundAtCenter() };Button("Clear") { app.clearManualMounds() }.disabled(store.configuration.manualMounds.isEmpty)
                    }
                    ForEach(Array(store.configuration.manualMounds.prefix(4).enumerated()),id:\.element.id) { i,mound in
                        slider("Mound \(i+1) height",value:Binding(get:{store.configuration.manualMounds.first(where:{$0.id==mound.id})?.height ?? mound.height},set:{height in store.update {if let index=$0.manualMounds.firstIndex(where:{$0.id==mound.id}) {$0.manualMounds[index].height=height}}}),range:1...150,format:"%.0f pt")
                    }
                    Text("This is manual geometry, independent of Finder detection. Add overlapping mounds for a taller pile.").font(.caption2).foregroundStyle(.secondary)
                }.padding(10)
            }
        }
    }

    private func slider(_ title:String,value:Binding<Float>,range:ClosedRange<Float>,format:String) -> some View {
        HStack(spacing:14) {
            Text(title).font(.system(size:12)).frame(width:128,alignment:.leading)
            Slider(value:value,in:range).accessibilityLabel(title)
            Text(String(format:format,value.wrappedValue)).font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary).frame(width:58,alignment:.trailing)
        }
    }
}
