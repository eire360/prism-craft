import Cocoa
import SwiftUI
import SceneKit
import UniformTypeIdentifiers

struct IslandProject: Codable {
 var version = 1
 var name: String
 var tiles: Int
 var weather: String
 var terrain: [String]?

 var valid: Bool {
 version == 1 && name.count <= 120 && (0...512).contains(tiles) && ["Sunny","Sunset","Storm"].contains(weather) && (terrain.map { $0.count == tiles && $0.allSatisfy { ["Woodland","Meadow","Pond"].contains($0) } } ?? true)
 }
}
final class StudioState: ObservableObject {
 @Published var lab = false
 @Published var name = "Untitled island"
 @Published var notice = "Your project is ready to build."
 @Published var zoom = 1.0
 @Published var terrain = "Woodland"
 var yaw = 0.40
 var pitch = 0.43
 var dragOrigin: CGPoint?
 let eye = SCNNode()
 weak var viewport: SCNView?
 init() {
 eye.camera = SCNCamera()
 eye.camera?.fieldOfView = 43
 eye.camera?.zFar = 600
 }
 func updateView(_ world: Playground) {
 guard let node = world.island else { return }
 let center = node.position
 let radius = CGFloat(2.5+Double((world.expansions+1)/2))*max(0.2,node.scale.x)
 let widthRatio = viewport.map { min(1,max(0.4,$0.bounds.width/max(1,$0.bounds.height))) } ?? 1
 let d = radius*3.25/CGFloat(zoom)/widthRatio
 eye.position = SCNVector3(center.x+sin(yaw)*cos(pitch)*d,center.y+sin(pitch)*d,center.z+cos(yaw)*cos(pitch)*d)
 eye.look(at:center)
 }
 func preset(_ name: String,world: Playground) {
 switch name {
 case "Front": yaw = 0;pitch = 0.07
 case "Top": yaw = 0;pitch = 1.54
 default: yaw = 0.40;pitch = 0.43;zoom = 1
 }
 updateView(world)
 }
 func drag(_ size: CGSize,world: Playground) {
 if dragOrigin == nil { dragOrigin = CGPoint(x:yaw,y:pitch) }
 guard let start = dragOrigin else { return }
 yaw = start.x-size.width*0.009
 pitch = min(1.54,max(-1.4,start.y+size.height*0.009))
 updateView(world)
 }
 func changeZoom(_ delta:Double,world: Playground) {
 zoom = min(3,max(0.45,zoom*delta));updateView(world)
 }
 func snapshot(_ world:Playground) -> IslandProject {
 IslandProject(name:String(name.prefix(120)),tiles:world.expansions,weather:world.weather,terrain:world.island?.childNodes.filter { $0.name?.hasPrefix("Expansion:") == true }.map { String(($0.name ?? "Expansion:Woodland").dropFirst(10)) })
 }
 func apply(_ project:IslandProject,world:Playground) {
 guard project.valid else { notice = "This island project is unsupported or damaged.";return }
 name = project.name;world.weather = project.weather;world.reset()
 for i in 0..<project.tiles { world.expandIsland(animated:false,terrain:project.terrain?[i] ?? "Woodland") }
 preset("Frame",world:world);notice = "Opened \(project.name)."
 }
 func save(_ world:Playground) {
 let project = snapshot(world)
 guard project.valid else { notice = "Projects can save up to 512 land additions.";return }
 let panel = NSSavePanel();panel.allowedContentTypes = [.json];panel.nameFieldStringValue = "Island.prism.json"
 panel.begin { result in
 guard result == .OK,let url = panel.url else { return }
 do { try JSONEncoder().encode(project).write(to:url,options:.atomic);self.notice = "Saved \(url.lastPathComponent)." }
 catch { self.notice = "Couldn’t save the project." }
 }
 }
 func open(_ world:Playground) {
 let panel = NSOpenPanel();panel.allowedContentTypes = [.json];panel.allowsMultipleSelection = false
 panel.begin { result in
 guard result == .OK,let url = panel.url else { return }
 do {
 let info = try url.resourceValues(forKeys:[.fileSizeKey])
 guard (info.fileSize ?? Int.max) <= 65536 else { self.notice = "That file is too large to be a Prism project.";return }
 self.apply(try JSONDecoder().decode(IslandProject.self,from:Data(contentsOf:url)),world:world)
 } catch { self.notice = "Couldn’t open that island project." }
 }
 }
 func exportImage() {
 guard let view = viewport,
 let tiff = view.snapshot().tiffRepresentation,
 let png = NSBitmapImageRep(data:tiff)?.representation(using:.png,properties:[:]) else { notice = "Couldn’t capture the island.";return }
 let panel = NSSavePanel();panel.allowedContentTypes = [.png];panel.nameFieldStringValue = "Island.png"
 panel.begin { result in
 guard result == .OK,let url = panel.url else { return }
 do { try png.write(to:url,options:.atomic);self.notice = "Exported \(url.lastPathComponent)." }
 catch { self.notice = "Couldn’t export the image." }
 }
 }
}
struct StudioViewport: NSViewRepresentable {
 @ObservedObject var state:StudioState
 @ObservedObject var world:Playground
 func makeNSView(context:Context) -> SCNView {
 let view = SCNView(frame:.zero,options:nil)
 view.backgroundColor = NSColor(red:0.073,green:0.105,blue:0.126,alpha:1)
 view.antialiasingMode = .multisampling2X
 view.preferredFramesPerSecond = 30
 view.scene = world.scene
 view.pointOfView = state.eye
 view.isPlaying = true
 state.viewport = view
 state.updateView(world)
 return view
 }
 func updateNSView(_ view:SCNView,context:Context) { state.updateView(world) }
}
struct IslandStudio: View {
 @ObservedObject var state:StudioState
 @ObservedObject var world:Playground
 var body: some View {
 VStack(spacing:0) {
 HStack {
 VStack(alignment:.leading,spacing:4) {
 Text("PRISM / ISLAND STUDIO").font(.system(size:11,weight:.semibold,design:.monospaced)).tracking(3).foregroundStyle(.mint)
 Text("Build a little world.").font(.system(size:26,weight:.medium))
 }
 Spacer()
 Button("Open Project…") { state.open(world) }
 Button("Save Project…") { state.save(world) }.keyboardShortcut("s")
 Button("Gesture Lab") { state.lab = true }
 }.padding(22)
 Divider()
 HStack(spacing:0) {
 ZStack(alignment:.bottomLeading) {
 StudioViewport(state:state,world:world).allowsHitTesting(false)
 Rectangle().fill(.clear).contentShape(Rectangle()).gesture(DragGesture(minimumDistance:1)
 .onChanged { state.drag($0.translation,world:world) }.onEnded { _ in state.dragOrigin = nil })
 Label("Drag to orbit",systemImage:"rotate.3d").font(.system(size:12,weight:.medium)).padding(12).background(.black.opacity(0.55)).clipShape(Capsule()).padding(18)
 }
 Divider()
 VStack(alignment:.leading,spacing:20) {
 VStack(alignment:.leading,spacing:8) {
 Text("PROJECT").font(.system(size:10,weight:.semibold,design:.monospaced)).tracking(2).foregroundStyle(.mint)
 TextField("Island name",text:$state.name).textFieldStyle(.roundedBorder)
 Text("\(world.expansions) land \(world.expansions == 1 ? "addition" : "additions")").foregroundStyle(.secondary).font(.callout)
 }
 VStack(alignment:.leading,spacing:8) {
 Text("Build").font(.headline)
 Picker("Terrain",selection:$state.terrain) { ForEach(["Woodland","Meadow","Pond"],id:\.self) { Text($0) } }
 Button { world.expandIsland(terrain:state.terrain);state.updateView(world) } label: { Label("Add land",systemImage:"plus.square").frame(maxWidth:.infinity) }
 .buttonStyle(.borderedProminent).tint(.teal)
 Button("Remove last tile") {
 if let tile = world.island?.childNodes.last(where:{$0.name?.hasPrefix("Expansion:") == true}) { tile.removeFromParentNode();world.expansions -= 1;state.updateView(world) }
 }.disabled(world.expansions == 0)
 Picker("Weather",selection:$world.weather) { ForEach(["Sunny","Sunset","Storm"],id:\.self) { Text($0) } }
 .onChange(of:world.weather) { world.setWeather() }
 }
 VStack(alignment:.leading,spacing:8) {
 Text("View").font(.headline)
 HStack { ForEach(["Front","Top","Frame"],id:\.self) { name in Button(name) { state.preset(name,world:world) } } }
 HStack {
 Button { state.changeZoom(1/1.2,world:world) } label:{ Image(systemName:"minus.magnifyingglass") }.accessibilityLabel("Zoom out")
 Text("\(Int(state.zoom*100))%").monospacedDigit().frame(minWidth:48)
 Button { state.changeZoom(1.2,world:world) } label:{ Image(systemName:"plus.magnifyingglass") }.accessibilityLabel("Zoom in")
 }
 }
 Spacer()
 Button { state.exportImage() } label: { Label("Export PNG…",systemImage:"photo") }
 Text(state.notice).font(.caption).foregroundStyle(.secondary).accessibilityLabel(state.notice)
 }.padding(20).frame(width:252)
 }
 }.background(Color(red:0.052,green:0.072,blue:0.083))
 .onAppear {
 world.update(hands:[HandEnergy(),HandEnergy()],mirrored:true,running:false)
 world.enabled = true;world.tableOn = false;world.setTable();world.scene.isPaused = false
 if world.exploded || world.islandHealth < 100 { world.rebuildIsland() }
 for node in world.objects where node.name != "Island" { node.isHidden = true }
 state.updateView(world)
 }.onDisappear { for node in world.objects where node.name != "Island" { node.isHidden = false } }
 }
}
