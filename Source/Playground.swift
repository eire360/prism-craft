import Cocoa
import SwiftUI
import SceneKit
import simd

private func add(_ a: SCNVector3,_ b: SCNVector3) -> SCNVector3 { SCNVector3(a.x+b.x,a.y+b.y,a.z+b.z) }
private func subtract(_ a: SCNVector3,_ b: SCNVector3) -> SCNVector3 { SCNVector3(a.x-b.x,a.y-b.y,a.z-b.z) }
private func multiply(_ a: SCNVector3,_ k: CGFloat) -> SCNVector3 { SCNVector3(a.x*k,a.y*k,a.z*k) }
private func length(_ a: SCNVector3) -> CGFloat { sqrt(a.x*a.x+a.y*a.y+a.z*a.z) }

struct GrabSignal {
 var down = false
 var valid = false
 var point = CGPoint(x:0.5,y:0.5)
 var palm: CGFloat = 0.07
 var pose = SCNVector3Zero
 var orientation: simd_quatf?
}
struct PinchGate {
 var closed = false
 mutating func update(gap:CGFloat,valid:Bool) -> Bool {
 guard valid else { return closed }
 if gap < 0.34 { closed = true }
 if gap > 0.62 { closed = false }
 return closed
 }
}
final class Playground: ObservableObject {
 @Published var tableOn = false
 @Published var orbitMode = false
 @Published var weather = "Sunny"
 @Published var tool = "Move"
 @Published var foregroundHands: [Bool] = [false,false]
 var pairAxis = SIMD3<Float>(1,0,0)
 var pairOrientation = simd_quatf(angle:0,axis:SIMD3<Float>(1,0,0))
 var pairPalms: [simd_quatf?] = [nil,nil]
 var pairSizes: [CGFloat] = [1,1]
 var pairPosition = SCNVector3Zero
 var pairMid = CGPoint.zero
 var pairTwist: Float = 0
 @Published var islandHealth = 100
 @Published var expansions = 0
 var exploded = false
 var fragments: [(SCNNode,SCNVector3,SCNVector4,SCNVector3,Bool)] = []
 var lastStrike = -100.0
 var toolPrevious = [CGPoint?](repeating:nil,count:2)
 var toolTime = CFAbsoluteTimeGetCurrent()
 var hammer = SCNNode()

 var weatherApplied = ""
 var gripPose = [SCNVector3Zero,SCNVector3Zero]
 var gripRotation = [SCNVector3Zero,SCNVector3Zero]
 var palmReference = [simd_quatf?](repeating:nil,count:2)
 var filteredOrientation = [simd_quatf?](repeating:nil,count:2)
 var gripOrientation = [simd_quatf(angle:0,axis:SIMD3<Float>(0,0,1)),simd_quatf(angle:0,axis:SIMD3<Float>(0,0,1))]
 var orbitOrientation = simd_quatf(angle:0,axis:SIMD3<Float>(0,0,1))
 private var appliedTable: Bool?
 var filteredPalm = [CGFloat(0.07),CGFloat(0.07)]
 var orbitStart: CGPoint?
 var orbitAngles = SCNVector3Zero
 var lastOrbitPalm: CGFloat = 0.07
 var orbitZoomDistance: CGFloat?
 var orbitZoomScale: CGFloat = 1
 var resizeAngle: CGFloat = 0
 var resizeRotation: CGFloat = 0
 @Published var enabled = true
 @Published var message = "Move the small ring onto a world · green cage means ready · pinch to grab"
 let scene = SCNScene()
 let eye = SCNNode()
 let table = SCNNode()
 var cursors: [SCNNode] = []
 var highlights: [SCNNode] = []
 weak var view: SCNView?
 var objects: [SCNNode] = []
 var grips: [SCNNode?] = [nil,nil]
 var gates = [PinchGate(),PinchGate()]
 var lastValid = [Double(-100),Double(-100)]
 var pinchWas = [false,false]
 var grabArmed = [false,false]
 var gripDepth = [CGFloat(0),CGFloat(0)]
 var gripPalm = [CGFloat(0.07),CGFloat(0.07)]
 var gripOffset = [SCNVector3Zero,SCNVector3Zero]
 var velocities: [ObjectIdentifier: SCNVector3] = [:]
 var previousPositions: [ObjectIdentifier: SCNVector3] = [:]
 var resizeNode: SCNNode?
 var resizeDistance: CGFloat = 0
 var resizeScale: CGFloat = 1
 var lastUpdate = CFAbsoluteTimeGetCurrent()
 var serial = 0
 init() {
 scene.background.contents = NSColor.clear
 scene.physicsWorld.gravity = SCNVector3(0,-7.5,0)
 scene.physicsWorld.timeStep = 1/120
 eye.camera = SCNCamera(); eye.camera!.fieldOfView = 48
 eye.camera!.zNear = 0.1; eye.camera!.zFar = 100
 eye.camera!.wantsHDR = false; eye.camera!.bloomIntensity = 0
 eye.camera!.bloomThreshold = 0.8; eye.camera!.bloomBlurRadius = 8
 eye.position = SCNVector3(0,1,11); scene.rootNode.addChildNode(eye)
 let key = SCNNode(); key.light = SCNLight(); key.light!.type = .omni
 key.light!.intensity = 700; key.light!.color = NSColor(red:0.7,green:0.86,blue:1,alpha:1)
 key.position = SCNVector3(-4,7,6); scene.rootNode.addChildNode(key)
 let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light!.type = .ambient; ambient.light!.intensity = 650
 scene.rootNode.addChildNode(ambient)
 let geometry = SCNBox(width:10,height:0.18,length:5,chamferRadius:0.09)
 let surface = SCNMaterial(); surface.diffuse.contents = NSColor(red:0.045,green:0.085,blue:0.11,alpha:1)
 surface.metalness.contents = 0.7; surface.roughness.contents = 0.3
 geometry.materials = [surface]; table.geometry = geometry
 table.position = SCNVector3(0,-0.9,1.0); table.physicsBody = SCNPhysicsBody.static()
 scene.rootNode.addChildNode(table)
 // Inlaid grid follows the actual horizontal tabletop in perspective.
 for i in -5...5 {
 let line = SCNNode(geometry:SCNBox(width:0.012,height:0.006,length:4.8,chamferRadius:0))
 line.position = SCNVector3(CGFloat(i)*0.9,0.095,0); line.geometry!.firstMaterial!.diffuse.contents = NSColor.cyan
 line.geometry!.firstMaterial!.emission.contents = NSColor.cyan.withAlphaComponent(0.25); table.addChildNode(line)
 }
 for i in -2...2 {
 let line = SCNNode(geometry:SCNBox(width:9.7,height:0.006,length:0.012,chamferRadius:0))
 line.position = SCNVector3(0,0.095,CGFloat(i)); line.geometry!.firstMaterial!.diffuse.contents = NSColor.cyan
 table.addChildNode(line)
 }
 for slot in 0..<2 {
 let cursor = SCNNode(geometry:SCNTorus(ringRadius:0.09,pipeRadius:0.016))
 cursor.eulerAngles.x = .pi/2
 cursor.geometry!.firstMaterial!.lightingModel = .constant
 cursor.geometry!.firstMaterial!.diffuse.contents = slot == 0 ? NSColor.green : NSColor.orange
 cursor.renderingOrder = 100
 cursor.geometry!.firstMaterial!.readsFromDepthBuffer = false
 scene.rootNode.addChildNode(cursor); cursor.isHidden = true; cursors.append(cursor)
 let highlight = SCNNode(geometry:SCNTorus(ringRadius:1.9,pipeRadius:0.012))
 highlight.eulerAngles.x = .pi/2

 highlight.geometry!.firstMaterial!.lightingModel = .constant
 highlight.geometry!.firstMaterial!.diffuse.contents = NSColor.green.withAlphaComponent(0.7)
 highlight.isHidden = true;scene.rootNode.addChildNode(highlight);highlights.append(highlight)
 }
 reset()
 }
 func attach(_ view:SCNView) { self.view = view; view.scene = scene; view.pointOfView = eye }
 func setTable() { guard appliedTable != tableOn else { return }; appliedTable = tableOn; table.isHidden = !tableOn; table.physicsBody = tableOn ? SCNPhysicsBody.static() : nil }
 func makeBody(_ node:SCNNode,held:Bool) {
 node.physicsBody = nil
 if node.name == "Island" { return }
 let radius = CGFloat(node.scale.x)*0.53
 let shape = SCNPhysicsShape(geometry:SCNSphere(radius:radius),options:nil)
 let body = SCNPhysicsBody(type:held ? .kinematic : .dynamic,shape:shape)
 body.mass = max(0.1,radius*radius*radius*3); body.restitution = 0.48; body.friction = 0.7
 body.rollingFriction = 0.5; body.damping = 0.16; body.angularDamping = 0.3
 body.continuousCollisionDetectionThreshold = 0.1
 node.physicsBody = body
 }
 func reset() {
 fragments = [];exploded = false;islandHealth = 100;expansions = 0;hammer.removeFromParentNode();hammer = SCNNode()
 for node in objects { node.removeFromParentNode() }
 weatherApplied = "";objects = []; grips = [nil,nil]; resizeNode = nil; velocities = [:]; previousPositions = [:]
 gates = [PinchGate(),PinchGate()]; pinchWas = [false,false]; grabArmed = [false,false]
 spawn("Island",position:SCNVector3(0,1,1))
 message = "Move the small ring onto a world · green cage means ready · pinch to grab"
 }
 func spawn(_ kind:String,position:SCNVector3? = nil) {
 guard objects.count < 10 else { message = "Ten worlds is the limit · reset the table to start fresh"; return }
 serial += 1
 if kind == "Island" { spawnIsland(position:position); return }
 let root = SCNNode(geometry:SCNSphere(radius:0.53)); root.name = kind
 let shell = root.geometry!.firstMaterial!
 shell.diffuse.contents = NSColor(red:0.02,green:0.04,blue:0.1,alpha:1)
 shell.specular.contents = NSColor.white; shell.roughness.contents = 0.24; shell.metalness.contents = 0.35
 let hue: CGFloat = kind == "Ocean" ? 0.52 : kind == "Galaxy" ? 0.76 : kind == "Storm" ? 0.6 : 0.08
 let tint = NSColor(calibratedHue:hue,saturation:0.8,brightness:1,alpha:1)
 shell.emission.contents = tint.withAlphaComponent(0.2)
 if kind == "Ocean" {
 shell.shaderModifiers = [.surface: """
 #pragma body
 float bands = sin(_surface.position.x*19.0 + sin(_surface.position.z*17.0+u_time)*2.0 + u_time*1.8);
 float land = sin(_surface.position.x*9.0+sin(_surface.position.y*12.0))*cos(_surface.position.z*11.0);
 _surface.diffuse.rgb = mix(float3(0.01,0.14,0.42),float3(0.03,0.75,0.65),smoothstep(0.2,0.65,land));
 _surface.emission.rgb = float3(0.02,0.15,0.23)+float3(0.03,0.25,0.35)*pow(max(0.0,bands),12.0);
 """]
 } else if kind == "Storm" {
 shell.shaderModifiers = [.surface: """
 #pragma body
 float cloud = sin(_surface.position.y*18.0+sin(_surface.position.x*14.0+u_time)*2.0);
 float flash = pow(max(0.0,sin(u_time*3.0+_surface.position.y*19.0)),40.0);
 _surface.diffuse.rgb = float3(0.06,0.09,0.2)+cloud*0.03;
 _surface.emission.rgb = float3(0.2,0.4,0.9)*flash*2.0;
 """]
 } else {
 // Individually modeled stars spiral inside the spherical world.
 for i in 0..<110 {
 let a = CGFloat(i)*2.39996
 let r = 0.46*sqrt(CGFloat(i)/110)
 let star = SCNNode(geometry:SCNSphere(radius:i%11 == 0 ? 0.018 : 0.008))
 star.position = SCNVector3(cos(a+r*8)*r,sin(a*3)*0.12,sin(a+r*8)*r)
 star.geometry!.firstMaterial!.lightingModel = .constant
 star.geometry!.firstMaterial!.diffuse.contents = i%3 == 0 ? NSColor.white : tint
 root.addChildNode(star)
 }
 shell.diffuse.contents = NSColor(red:0.04,green:0.01,blue:0.1,alpha:0.45)
 shell.transparency = 0.4; shell.isDoubleSided = true
 }
 let ring = SCNNode(geometry:SCNTorus(ringRadius:0.59,pipeRadius:0.012))
 ring.eulerAngles = SCNVector3(0.5,0,0.25); ring.geometry!.firstMaterial!.emission.contents = tint
 ring.geometry!.firstMaterial!.diffuse.contents = tint; root.addChildNode(ring)
 ring.runAction(.repeatForever(.rotateBy(x:0,y:1,z:0,duration:5)))
 let light = SCNNode(); light.light = SCNLight(); light.light!.type = .omni
 light.light!.color = tint; light.light!.intensity = 110; light.light!.attenuationEndDistance = 4
 root.addChildNode(light)
 root.position = position ?? SCNVector3(CGFloat((serial%5)-2)*1.2,2,0)
 scene.rootNode.addChildNode(root); objects.append(root); makeBody(root,held:false)
 }

 func spawnIsland(position:SCNVector3?) {
 let root = SCNNode(); root.name = "Island"
 func material(_ color:NSColor) -> SCNMaterial { let m = SCNMaterial();m.diffuse.contents = color;m.roughness.contents = 1;m.lightingModel = .lambert;return m }
 let soil = material(NSColor(red:0.32,green:0.22,blue:0.15,alpha:1))
 let stone = material(NSColor(red:0.39,green:0.4,blue:0.38,alpha:1))
 let grass = material(NSColor(red:0.32,green:0.57,blue:0.24,alpha:1))
 func node(_ geometry:SCNGeometry,_ position:SCNVector3,_ mat:SCNMaterial) -> SCNNode {
 let n = SCNNode(geometry:geometry);geometry.materials = [mat];n.position = position;root.addChildNode(n);return n
 }
 _ = node(SCNBox(width:3,height:0.65,length:2.4,chamferRadius:0.06),SCNVector3(0,-0.2,0),soil)
 _ = node(SCNBox(width:2.88,height:0.14,length:2.3,chamferRadius:0.03),SCNVector3(0,0.2,0),grass)
 for i in 0..<3 {
 let width = 2.7-CGFloat(i)*0.48
 _ = node(SCNBox(width:width,height:0.16,length:2.15-CGFloat(i)*0.4,chamferRadius:0.03),SCNVector3(CGFloat(i)*0.06,-0.59-CGFloat(i)*0.15,0),i%2 == 0 ? stone : soil)
 }
 let water = material(NSColor(red:0.14,green:0.62,blue:0.74,alpha:1))
 // A lake and a stream run across the grass and spill over the cut edge.
 let lake = node(SCNCylinder(radius:0.5,height:0.022),SCNVector3(0.6,0.285,0.2),water);lake.scale = SCNVector3(1,1,0.7)
 for i in 0..<6 {
 let x = 0.62+sin(CGFloat(i)*0.8)*0.13
 _ = node(SCNBox(width:0.17,height:0.025,length:0.23,chamferRadius:0.025),SCNVector3(x,0.285,0.35+CGFloat(i)*0.15),water)
 }
 _ = node(SCNBox(width:0.17,height:1.25,length:0.025,chamferRadius:0.01),SCNVector3(0.52,-0.32,1.21),water)
 let trunk = material(NSColor(red:0.28,green:0.18,blue:0.1,alpha:1))
 for i in 0..<9 {
 let x = -1.12+CGFloat(i%3)*0.45
 let z = -0.8+CGFloat(i/3)*0.62
 let height = 0.38+CGFloat(i%3)*0.09
 _ = node(SCNCylinder(radius:0.035,height:height),SCNVector3(x,0.27+height/2,z),trunk)
 let leaves = material(NSColor(red:0.1+CGFloat(i%3)*0.035,green:0.31+CGFloat(i%3)*0.04,blue:0.17,alpha:1))
 let crown = SCNCone(topRadius:0,bottomRadius:0.2,height:height*1.3);crown.radialSegmentCount = 7
 _ = node(crown,SCNVector3(x,0.5+height*0.5,z),leaves)
 }
 let mountain = SCNCone(topRadius:0.05,bottomRadius:0.4,height:0.75);mountain.radialSegmentCount = 5
 _ = node(mountain,SCNVector3(0.65,0.63,-0.65),stone)
 let snow = material(NSColor(white:0.89,alpha:1))
 let peak = SCNCone(topRadius:0,bottomRadius:0.17,height:0.29);peak.radialSegmentCount = 5
 _ = node(peak,SCNVector3(0.65,0.9,-0.65),snow)
 let house = material(NSColor(red:0.86,green:0.73,blue:0.48,alpha:1))
 _ = node(SCNBox(width:0.36,height:0.28,length:0.32,chamferRadius:0.01),SCNVector3(-0.15,0.42,0.65),house)
 let roof = material(NSColor(red:0.56,green:0.22,blue:0.13,alpha:1))
 _ = node(SCNPyramid(width:0.47,height:0.22,length:0.43),SCNVector3(-0.15,0.56,0.65),roof)
 root.position = position ?? SCNVector3(0,1,1)
 root.eulerAngles = SCNVector3(0.26,-0.4,0)
 scene.rootNode.addChildNode(root);objects.append(root)
 weatherApplied = "";setWeather()
 }


 func setWeather() {
 guard weatherApplied != weather else { return }
 weatherApplied = weather
 for island in objects where island.name == "Island" {
 island.childNode(withName:"Weather",recursively:false)?.removeFromParentNode()
 let group = SCNNode();group.name = "Weather";island.addChildNode(group)
 func solid(_ color:NSColor) -> SCNMaterial { let m = SCNMaterial();m.diffuse.contents = color;m.lightingModel = .constant;return m }
 if weather == "Storm" {
 for i in 0..<6 {
 let cloud = SCNNode(geometry:SCNSphere(radius:0.28+CGFloat(i%2)*0.08))
 (cloud.geometry as? SCNSphere)?.segmentCount = 12
 cloud.geometry!.materials = [solid(NSColor(white:0.4+CGFloat(i%3)*0.04,alpha:1))]
 cloud.position = SCNVector3(-0.85+CGFloat(i)*0.33,1.6+sin(CGFloat(i))*0.08,-0.1)
 cloud.scale = SCNVector3(1.3,0.55,1)
 group.addChildNode(cloud)
 }
 let rain = SCNParticleSystem();rain.birthRate = 90;rain.particleLifeSpan = 0.65
 rain.particleSize = 0.012;rain.particleVelocity = 1.6;rain.emittingDirection = SCNVector3(0,-1,0)
 rain.particleColor = NSColor(red:0.5,green:0.75,blue:0.88,alpha:0.7)
 rain.isLightingEnabled = false;rain.blendMode = .alpha;rain.stretchFactor = 0.08
 rain.emitterShape = SCNBox(width:2.1,height:0.01,length:1.5,chamferRadius:0)
 rain.acceleration = SCNVector3(0,-0.2,0);rain.loops = true
 let emitter = SCNNode();emitter.position = SCNVector3(0,1.4,0);emitter.addParticleSystem(rain);group.addChildNode(emitter)
 } else if weather == "Sunset" {
 for i in 0..<14 {
 let firefly = SCNNode(geometry:SCNSphere(radius:0.015))
 firefly.geometry!.materials = [solid(NSColor(red:1,green:0.78,blue:0.3,alpha:1))]
 let a = CGFloat(i)*2.399
 firefly.position = SCNVector3(cos(a)*1.2,0.45+CGFloat(i%4)*0.14,sin(a))
 group.addChildNode(firefly)
 firefly.runAction(.repeatForever(.sequence([.moveBy(x:0.08,y:0.13,z:0.05,duration:1.4+Double(i%3)*0.3),.moveBy(x:-0.08,y:-0.13,z:-0.05,duration:1.4+Double(i%3)*0.3)])))
 }
 let sun = SCNNode(geometry:SCNSphere(radius:0.19));sun.geometry!.materials = [solid(NSColor(red:1,green:0.6,blue:0.28,alpha:1))]
 sun.position = SCNVector3(1.15,0.75,-1.1);group.addChildNode(sun)
 } else {
 for i in 0..<3 {
 let pivot = SCNNode();pivot.position = SCNVector3(0,1.1+CGFloat(i)*0.14,0);group.addChildNode(pivot)
 let bird = SCNNode();bird.position = SCNVector3(0.8+CGFloat(i)*0.17,0,0)
 for side in [-1,1] {
 let wing = SCNNode(geometry:SCNBox(width:0.1,height:0.012,length:0.035,chamferRadius:0))
 wing.geometry!.materials = [solid(NSColor(white:0.92,alpha:1))];wing.position.x = CGFloat(side)*0.04;wing.eulerAngles.z = CGFloat(side)*0.4
 wing.runAction(.repeatForever(.sequence([.rotateBy(x:0,y:0,z:CGFloat(side)*0.5,duration:0.3),.rotateBy(x:0,y:0,z:-CGFloat(side)*0.5,duration:0.3)])))
 bird.addChildNode(wing)
 }
 pivot.addChildNode(bird);pivot.runAction(.repeatForever(.rotateBy(x:0,y:CGFloat.pi*2,z:0,duration:8+Double(i)*2)))
 }
 }
 }
 }

 func signal(_ hand:HandEnergy,slot:Int,mirrored:Bool,now:Double) -> GrabSignal {
 guard hand.seen,let thumb = hand.joints[.thumbTip],let index = hand.joints[.indexTip],let wrist = hand.joints[.wrist],let knuckle = hand.joints[.middleMCP] else { return GrabSignal(down:gates[slot].closed) }
 func dist(_ a:CGPoint,_ b:CGPoint) -> CGFloat { hypot(a.x-b.x,(a.y-b.y)*9/16) }
 let measured = max(0.02,dist(wrist,knuckle))
 let palmEdges = [hand.joints[.indexMCP],hand.joints[.littleMCP]].compactMap { $0 }
 let width = palmEdges.count == 2 ? dist(palmEdges[0],palmEdges[1]) : measured
 let palm = max(measured,width*0.85)
 filteredPalm[slot] += (palm-filteredPalm[slot])*0.2
 let down = gates[slot].update(gap:dist(thumb,index)/palm,valid:true)
 lastValid[slot] = now
 let x = (thumb.x+index.x)*0.5
 let midpoint = CGPoint(x:x,y:(thumb.y+index.y)*0.5)
 let dx = (knuckle.x-wrist.x)*(mirrored ? -1 : 1)
 let dy = (knuckle.y-wrist.y)*9/16


 let roll = -atan2(dx,-dy)
 return GrabSignal(down:down,valid:true,point:CGPoint(x:mirrored ? 1-x : x,y:midpoint.y),palm:filteredPalm[slot],pose:SCNVector3(0,0,roll),orientation:PalmPose.estimate(hand.joints,mirrored:mirrored))
 }
 func screenPoint(_ signal:GrabSignal) -> CGPoint {
 guard let view else { return .zero }
 let w = min(view.bounds.width,view.bounds.height*16/9),h = w*9/16
 return CGPoint(x:(view.bounds.width-w)/2+signal.point.x*w,y:(view.bounds.height-h)/2+(1-signal.point.y)*h)
 }
 func worldPoint(_ signal:GrabSignal,z:CGFloat) -> SCNVector3 {
 guard let view else { return SCNVector3Zero }
 let depth = view.projectPoint(SCNVector3(0,0,z)).z
 let point = screenPoint(signal)
 return view.unprojectPoint(SCNVector3(point.x,point.y,depth))
 }
 func nearest(_ signal:GrabSignal) -> SCNNode? {
 guard let view,view.bounds.width > 0 else { return nil }
 var best: SCNNode?; var bestDistance: CGFloat = 10000
 let cursor = screenPoint(signal)
 for node in objects where node.presentation.position.y > -8 {
 let position = node.presentation.worldPosition
 let screen = view.projectPoint(position)
 let edge = view.projectPoint(add(position,SCNVector3(CGFloat(node.scale.x)*(node.name == "Island" ? 1.9+CGFloat((expansions+1)/2) : 0.7),0,0)))
 let radius = max(40,abs(edge.x-screen.x))
 let distance = hypot(screen.x-cursor.x,screen.y-cursor.y)
 if distance < max(85,radius+50) && distance < bestDistance { best = node; bestDistance = distance }
 }
 return best
 }
 func release(_ slot:Int) {
 guard let node = grips[slot] else { return }
 grips[slot] = nil
 if grips.contains(where: { $0 === node }) { return }
 if node.name == "Island" { node.physicsBody = nil; message = "Island anchored · pinch to reposition · Inspect to orbit"; return }
 let position = node.presentation.position
 node.position = position; makeBody(node,held:false)
 let velocity = velocities[ObjectIdentifier(node)] ?? SCNVector3Zero
 node.physicsBody!.velocity = multiply(velocity,min(1,9/max(0.01,length(velocity))))
 node.physicsBody!.angularVelocity = SCNVector4(0.3,1,0.2,2)
 node.physicsBody!.resetTransform()
 }
 func update(hands:[HandEnergy],mirrored:Bool,running:Bool,now:Double = CFAbsoluteTimeGetCurrent()) {
 guard now-lastUpdate > 0.008 else { return }
 let dt = min(0.1,max(0.008,now-lastUpdate)); lastUpdate = now
 setTable();setWeather()
 if !enabled || !running { grabArmed = [false,false];release(0);release(1); for cursor in cursors { cursor.isHidden = true }; for highlight in highlights { highlight.isHidden = true };scene.isPaused = !enabled;return }
 scene.isPaused = false
 var signals = (0..<2).map { signal(hands[$0],slot:$0,mirrored:mirrored,now:now) }
 let poses = hands.map { hand -> Int in
 guard hand.seen, let wrist = hand.joints[.wrist], let knuckle = hand.joints[.middleMCP] else { return 0 }
 let base = hypot(wrist.x-knuckle.x,(wrist.y-knuckle.y)*9/16)
 let tips = [hand.joints[.indexTip],hand.joints[.middleTip],hand.joints[.ringTip],hand.joints[.littleTip]].compactMap { $0 }
 guard base > 0.02, tips.count == 4 else { return 0 }
 let extended = tips.filter { hypot($0.x-wrist.x,($0.y-wrist.y)*9/16) > base*1.4 }.count
 return extended == 0 ? 1 : extended == 4 ? 2 : 0
 }
 for slot in 0..<2 where poses[slot] == 1 { signals[slot].down = false; gates[slot].closed = false }
 let nextTool = orbitMode || signals.contains(where: { $0.valid && $0.down }) || grips.contains(where: { $0 != nil }) ? "Move" : poses.contains(1) ? (poses.contains(2) ? "Hammer" : "Punch") : "Move"
 if nextTool != tool { tool = nextTool; toolPrevious = [nil,nil] }
 let front = (0..<2).map { slot -> Bool in
 guard hands[slot].seen, signals[slot].valid, let island else { return false }
 if grips[slot] === island { return true }
 let measured = signals[slot].palm
 let threshold = 0.075*10/max(3,11-island.position.z)
 return measured > threshold*(foregroundHands[slot] ? 0.92 : 1.08)
 }
 if front != foregroundHands { foregroundHands = front }
 for slot in 0..<2 {
 let input = signals[slot]
 let target = input.valid ? (grips[slot] ?? nearest(input)) : nil
 cursors[slot].isHidden = !input.valid
 cursors[slot].position = worldPoint(input,z:target?.presentation.position.z ?? 1.5)
 let cursorScale:CGFloat = input.down ? 0.65 : 1
 cursors[slot].scale = SCNVector3(cursorScale,cursorScale,cursorScale)
 highlights[slot].isHidden = target == nil
 if let target { highlights[slot].position = target.presentation.position;highlights[slot].scale = target.scale }
 }
 for slot in 0..<2 {
 let input = signals[slot]
 if !input.valid {
 grabArmed[slot] = false
 if now-lastValid[slot] > 0.65 { release(slot);gates[slot].closed = false;pinchWas[slot] = false }
 continue
 }
 let freshPinch = input.down && grabArmed[slot] && !pinchWas[slot]
 grabArmed[slot] = !input.down && poses[slot] != 1
 if tool == "Move" && !orbitMode && freshPinch && grips[slot] == nil,let node = nearest(input) {
 let position = node.presentation.position
 node.position = position; makeBody(node,held:true)
 grips[slot] = node; gripDepth[slot] = position.z; gripPalm[slot] = input.palm;gripPose[slot] = input.pose;gripRotation[slot] = node.eulerAngles;gripOrientation[slot] = node.simdOrientation;palmReference[slot] = input.orientation
 gripOffset[slot] = subtract(position,worldPoint(input,z:position.z))
 velocities[ObjectIdentifier(node)] = SCNVector3Zero
 }
 if !input.down && pinchWas[slot] { release(slot) }
 pinchWas[slot] = input.down
 }
 if tool != "Move" {
 release(0);release(1)
 updateTools(hands:hands,signals:signals,mirrored:mirrored,now:now)
 return
 }
 hammer.isHidden = true
 if orbitMode {
 release(0);release(1)
 if signals.allSatisfy({ $0.valid && $0.down }),let island = objects.first(where: { $0.name == "Island" }) {
 let distance = max(0.03,hypot(signals[0].point.x-signals[1].point.x,(signals[0].point.y-signals[1].point.y)*9/16))
 if orbitZoomDistance == nil { orbitZoomDistance = distance;orbitZoomScale = island.scale.x }
 let size = max(0.2,min(4,orbitZoomScale*distance/orbitZoomDistance!))
 let smooth = island.scale.x+(size-island.scale.x)*0.3
 island.scale = SCNVector3(smooth,smooth,smooth)
 orbitStart = nil
 message = "INSPECT ZOOM · spread two pinches to enlarge · one pinch to orbit"
 return
 }
 orbitZoomDistance = nil
 if let input = signals.first(where: { $0.valid && $0.down }),let island = objects.first(where: { $0.name == "Island" }) {
 if orbitStart == nil { orbitStart = input.point;orbitAngles = island.eulerAngles;orbitOrientation = island.simdOrientation;lastOrbitPalm = input.palm }
 let start = orbitStart!
 let dx = input.point.x-start.x, dy = input.point.y-start.y
let yaw = simd_quatf(angle:Float(dx*2.8),axis:SIMD3<Float>(0,1,0))
let pitch = simd_quatf(angle:Float(dy*2.8),axis:SIMD3<Float>(1,0,0))
island.simdOrientation = pitch*yaw*orbitOrientation
 message = "INSPECT · drag left/right to turn · up/down to tilt · release to regrip"
 } else { orbitStart = nil;message = "INSPECT · pinch anywhere and drag to orbit the floating island" }
 return
 }
 orbitStart = nil;orbitZoomDistance = nil
 if let a = grips[0], let b = grips[1],a === b {
 let mid = CGPoint(x:(signals[0].point.x+signals[1].point.x)/2,y:(signals[0].point.y+signals[1].point.y)/2)
 if signals.allSatisfy(\.valid) {
 if resizeNode !== a {
 resizeNode = a; resizeScale = a.scale.x; pairOrientation = a.simdOrientation
 pairSizes = signals.map { $0.palm }; pairPalms = signals.map { $0.orientation }
 pairPosition = a.position; pairMid = mid; pairTwist = 0
 let span = SIMD3<Float>(Float(signals[1].point.x-signals[0].point.x),Float((signals[0].point.y-signals[1].point.y)*9/16),0)
 resizeDistance = CGFloat(max(0.035,simd_length(span))); pairAxis = span/Float(resizeDistance)
 if simd_length(pairAxis) < 0.5 { pairAxis = SIMD3(1,0,0) } else { pairAxis = simd_normalize(pairAxis) }
 }
 let ratios = (0..<2).map { max(0.55,min(1.8,signals[$0].palm/max(0.025,pairSizes[$0]))) }
 let mean = (ratios[0]+ratios[1])/2
 let span = SIMD3<Float>(Float(signals[1].point.x-signals[0].point.x),Float((signals[0].point.y-signals[1].point.y)*9/16),Float((ratios[1]-ratios[0])*0.28))
 let distance = max(0.025,CGFloat(simd_length(span)))
 let axis = simd_normalize(span+SIMD3<Float>(0.000001,0,0))
 let swing = simd_quatf(from:pairAxis,to:axis)
 let twists = (0..<2).compactMap { i -> Float? in
 guard let pose = signals[i].orientation, let start = pairPalms[i] else { return nil }
 let q = pose*start.inverse
 let t = 2*atan2(simd_dot(q.imag,axis),q.real)
 let wrapped = atan2(sin(t),cos(t))
 return abs(wrapped) < 1.7 ? wrapped : nil
 }
 if !twists.isEmpty { pairTwist += ((twists.reduce(0,+)/Float(twists.count))-pairTwist)*0.25 }
 let rotation = simd_quatf(angle:pairTwist,axis:axis)*swing*pairOrientation
 a.simdOrientation = simd_slerp(a.simdOrientation,rotation,0.4)
 let targetScale = min(4,max(0.2,resizeScale*distance/resizeDistance/mean))
 let smooth = a.scale.x+(targetScale-a.scale.x)*0.25
 a.scale = SCNVector3(smooth,smooth,smooth)
 let z = min(6,max(-6,11-(11-pairPosition.z)/mean))
 let offset = subtract(pairPosition,worldPoint(GrabSignal(point:pairMid),z:pairPosition.z))
 let target = add(worldPoint(GrabSignal(point:mid),z:z),offset)
 a.position = add(multiply(a.position,0.6),multiply(target,0.4))
 }
 message = "TWO-HAND GRIP · turn both palms forward to tilt · spread to resize"
 } else {
 if resizeNode != nil {
 // Rebase the remaining grip after two-hand scaling so it never snaps.
 for slot in 0..<2 { if let node = grips[slot] { gripDepth[slot] = node.position.z;gripPalm[slot] = signals[slot].palm;gripPose[slot] = signals[slot].pose;gripRotation[slot] = node.eulerAngles;gripOrientation[slot] = node.simdOrientation;palmReference[slot] = signals[slot].orientation;gripOffset[slot] = subtract(node.position,worldPoint(signals[slot],z:node.position.z)) } }
 resizeNode = nil
 }
 for slot in 0..<2 {
 guard let node = grips[slot],signals[slot].valid else { continue }
 let input = signals[slot]
 // Apparent palm size varies inversely with camera distance.
 let baseline = max(0.025,gripPalm[slot])
 let ratio = max(0.45,min(2.2,input.palm/baseline))
 let depth = min(6,max(-6,11-(11-gripDepth[slot])/ratio))
 var target = add(worldPoint(input,z:depth),gripOffset[slot])
 if tableOn && node.name != "Island" { target.y = max(-0.75+node.scale.y*0.53,target.y) }
 node.position = add(multiply(node.position,0.55),multiply(target,0.45))
 func wrapped(_ angle:CGFloat) -> CGFloat { atan2(sin(angle),cos(angle)) }
 let roll = wrapped(input.pose.z-gripPose[slot].z)
 let deadZone:CGFloat = 0.04
 let adjusted = abs(roll) < deadZone ? 0 : roll-(roll > 0 ? deadZone : -deadZone)
 // Apply roll around the viewer's axis, independent of the object's current tilt.
 var desired = simd_quatf(angle:Float(adjusted),axis:SIMD3<Float>(0,0,1))*gripOrientation[slot]
 if let pose = input.orientation,let reference = palmReference[slot] {
 let delta = simd_normalize(pose*reference.inverse)
 // Reject near-singular planar flips instead of snapping the object.
 if delta.angle < 2.6 { desired = delta*gripOrientation[slot] } else { desired = node.simdOrientation }
 } else if palmReference[slot] != nil { desired = node.simdOrientation }
 node.simdOrientation = simd_slerp(node.simdOrientation,desired,0.3)
 let id = ObjectIdentifier(node)
 let previous = previousPositions[id] ?? node.position
 let velocity = multiply(subtract(node.position,previous),1/dt)
 velocities[id] = add(multiply(velocities[id] ?? SCNVector3Zero,0.6),multiply(velocity,0.4))
 previousPositions[id] = node.position
 }
 let held = grips.compactMap { $0?.name }
 let ready = signals.filter(\.valid).compactMap { nearest($0)?.name }.first
 message = held.isEmpty ? (ready.map { "READY · \($0) · pinch now to grab" } ?? "Move the small ring onto a world · green cage means ready · pinch to grab") : "HOLDING · "+held.joined(separator:" + ")+" · roll wrist to rotate · closer/farther for depth · release anchors"
 }
 // Expired fallen objects are recycled only when they have left the visible stage.
 for node in objects where node.presentation.position.y < -14 && !grips.contains(where: { $0 === node }) {
 node.position = SCNVector3(CGFloat((objects.firstIndex(of:node) ?? 0)-1)*1.8,1,0)
 node.physicsBody?.resetTransform(); node.physicsBody?.clearAllForces();node.physicsBody?.velocity = SCNVector3Zero
 }
 }
}
struct PlaygroundView: NSViewRepresentable {
 @ObservedObject var world: Playground
 let hands:[HandEnergy]
 let mirrored:Bool
 let running:Bool
 func makeNSView(context:Context) -> SCNView {
 let view = SCNView(frame:.zero,options:nil)
 view.backgroundColor = NSColor.clear
 view.antialiasingMode = .multisampling2X; view.preferredFramesPerSecond = 30
 world.attach(view); view.isPlaying = true; view.rendersContinuously = true
 return view
 }
 func updateNSView(_ view:SCNView,context:Context) {
 world.setTable();world.scene.isPaused = !world.enabled
 DispatchQueue.main.async { world.update(hands:hands,mirrored:mirrored,running:running) }
 }
}
