import Cocoa
import AVFoundation
import Vision
import SwiftUI
import CoreImage

struct HandEnergy {
 var center = CGPoint(x:0.5,y:0.5)
 var radius: CGFloat = 0.05
 var power: CGFloat = 0
 var mode = 0
 var candidate = 0
 var stableFrames = 0
 var joints: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
 var trail: [CGPoint] = []
 var seen = false
 var wrist = CGPoint(x:0.5,y:0.5)
 var lastSeen: Double = -100
 var closedFrames = 0
}
struct Fusion {
 let center: CGPoint
 let radius: CGFloat
 let amount: CGFloat
 let mode: Int
 let label: String
 static let names = ["Plasma", "Lightning", "Portal", "Singularity"]
 static func make(_ hands: [HandEnergy]) -> Fusion {
 let a = hands[0], b = hands[1]
 let weight = a.radius*a.radius / max(0.0001,a.radius*a.radius+b.radius*b.radius)
 let center = CGPoint(x:a.center.x*weight+b.center.x*(1-weight),y:a.center.y*weight+b.center.y*(1-weight))
 let distance = hypot(a.center.x-b.center.x,(a.center.y-b.center.y)*9/16)
 let reach = (a.radius+b.radius)*1.7
 let raw = min(1,max(0,(reach-distance)/max(0.01,reach*0.65)))
 let amount = raw*raw*(3-2*raw) * min(a.power,b.power)
 let lo = min(a.mode,b.mode), hi = max(a.mode,b.mode)
 let pair = lo*4+hi
 let recipe: (Int,String)
 switch pair {
 case 0: recipe = (4,"Supernova")
 case 5: recipe = (5,"Thunder core")
 case 10: recipe = (6,"Double vortex")
 case 15: recipe = (7,"Event horizon")
 case 1: recipe = (8,"Ion storm")
 case 2: recipe = (9,"Solar gate")
 case 3: recipe = (10,"Collapsing star")
 case 6: recipe = (11,"Rift storm")
 case 7: recipe = (12,"Dark lightning")
 default: recipe = (13,"Wormhole")
 }
 return Fusion(center:center,radius:min(0.2,sqrt(a.radius*a.radius+b.radius*b.radius)*1.22),amount:amount,mode:recipe.0,label:recipe.1)
 }
}
struct FusionHold {
 var held: Fusion?
 var approachSince: Double?
 var separateSince: Double?
 var bothSeenAt: Double = -100
 mutating func update(_ hands: [HandEnergy], now: Double) -> Fusion {
 let raw = Fusion.make(hands)
 let distance = hypot(hands[0].center.x-hands[1].center.x,(hands[0].center.y-hands[1].center.y)*9/16)
 let both = hands.allSatisfy { $0.seen && $0.power > 0.45 }
 if both { bothSeenAt = now }
 let enter = max(0.16,(hands[0].radius+hands[1].radius)*1.8)
 let exit = max(0.28,enter*1.65)
 if held == nil {
 if both && distance < enter {
 if approachSince == nil { approachSince = now }
 if now-approachSince! > 0.12 { held = Fusion(center:raw.center,radius:raw.radius,amount:1,mode:raw.mode,label:raw.label) }
 } else { approachSince = nil }
 }
 if let previous = held {
 if both && distance > exit {
 if separateSince == nil { separateSince = now }
 if now-separateSince! > 0.22 { held = nil; approachSince = nil; separateSince = nil; return raw }
 } else { separateSince = nil }
 if now-bothSeenAt > 1.1 { held = nil; approachSince = nil; return raw }
 let center = both ? CGPoint(x:previous.center.x+(raw.center.x-previous.center.x)*0.2,y:previous.center.y+(raw.center.y-previous.center.y)*0.2) : previous.center
 let result = Fusion(center:center,radius:previous.radius,amount:1,mode:previous.mode,label:previous.label)
 held = result; return result
 }
 // A gentle approach, followed by a stable latched core.
 return Fusion(center:raw.center,radius:raw.radius,amount:min(0.55,raw.amount),mode:raw.mode,label:raw.label)
 }
}
final class Camera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
 let session = AVCaptureSession()
 let queue = DispatchQueue(label: "prism.camera")
 @Published var status = "Camera is off"
 @Published var running = false
 @Published var demo = false
 @Published var playgroundOn = true
 @Published var energyOn = false
 @Published var mirrored = true
 @Published var showTracking = true
 @Published var frame: CGImage?
 var frameStarted: Double = 0
 var headYaw: Double?
 let faceRequest: VNDetectFaceRectanglesRequest = {
 let r = VNDetectFaceRectanglesRequest();r.revision = VNDetectFaceRectanglesRequestRevision3;return r
 }()
 var lastFaceAt = 0.0
 var cachedYaw: Double?
 @Published var hands = [HandEnergy(),HandEnergy()]
 var tracked = [HandEnergy(),HandEnergy()]
 var fusionHold = FusionHold()
 @Published var fusionAmount: CGFloat = 0
 let renderer = Relighter()
 let handRequest: VNDetectHumanHandPoseRequest = { let request = VNDetectHumanHandPoseRequest();request.maximumHandCount = 2;return request }()
 var lastCapture: Double = 0
 func start() {
  AVCaptureDevice.requestAccess(for: .video) { allowed in
   guard allowed else { DispatchQueue.main.async { self.status = "Allow camera access in System Settings → Privacy & Security → Camera" }; return }
   self.queue.async {
    if self.session.inputs.isEmpty {
     self.session.beginConfiguration(); self.session.sessionPreset = .hd1280x720
     guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(input) else { self.session.commitConfiguration(); DispatchQueue.main.async { self.status = "No available camera" }; return }
     self.session.addInput(input)
     let output = AVCaptureVideoDataOutput(); output.alwaysDiscardsLateVideoFrames = true
     output.setSampleBufferDelegate(self, queue: self.queue)
     guard self.session.canAddOutput(output) else { self.session.commitConfiguration(); return }
     self.session.addOutput(output)
     if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
      connection.automaticallyAdjustsVideoMirroring = false
      connection.isVideoMirrored = false
     }
     self.session.commitConfiguration()
    }
    self.session.startRunning()
    DispatchQueue.main.async { self.running = true; self.status = "Show an open palm" }
   }
  }
 }
 func stop() { queue.async {
 self.session.stopRunning(); self.tracked = [HandEnergy(),HandEnergy()]; self.fusionHold = FusionHold()
 DispatchQueue.main.async { self.running = false; self.hands = self.tracked; self.status = "Camera is off" }
 } }
 func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
 let now = CFAbsoluteTimeGetCurrent()
 guard now-lastCapture >= 1.0/45.0 else { return };lastCapture = now
 let closeTogether = hypot(tracked[0].center.x-tracked[1].center.x,(tracked[0].center.y-tracked[1].center.y)*9/16) < 0.25 && tracked.allSatisfy { $0.power > 0.4 }
 let freezeShape = closeTogether || fusionHold.held != nil
 let request = handRequest
 do {
 guard let trackingBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
 let trackingImage = CIImage(cvPixelBuffer:trackingBuffer).transformed(by:CGAffineTransform(scaleX:0.6,y:0.6))
 let handler = VNImageRequestHandler(ciImage:trackingImage,orientation:.up)
 try handler.perform([request])
 if now-lastFaceAt >= 0.047 {
 lastFaceAt=now;cachedYaw=nil
 if (try? handler.perform([faceRequest])) != nil, let faces=faceRequest.results,faces.count == 1 {
 cachedYaw=faces[0].yaw?.doubleValue
 }
 }
 var observations: [(CGPoint,[VNHumanHandPoseObservation.JointName: VNRecognizedPoint])] = []
 for hand in request.results ?? [] {
 let points = try hand.recognizedPoints(.all)
 if let wrist = points[.wrist], wrist.confidence > 0.25 { observations.append((wrist.location,points)) }
 }
 // Match against previous wrists, testing both assignments when two hands are visible.
 func cost(_ observation: Int,_ slot: Int) -> CGFloat {
 let previous = tracked[slot].wrist
 return hypot(observations[observation].0.x-previous.x,observations[observation].0.y-previous.y)
 }
 var assignments: [(Int,Int)] = []
 if observations.count == 2 {
 let swapped = cost(0,1)+cost(1,0) < cost(0,0)+cost(1,1)
 assignments = [(0,swapped ? 1 : 0),(1,swapped ? 0 : 1)]
 } else if observations.count == 1 { assignments = [(0,cost(0,0) <= cost(0,1) ? 0 : 1)] }
 for slot in 0..<2 { tracked[slot].seen = false }
 for (observation,slot) in assignments {
 let points = observations[observation].1
 func p(_ joint: VNHumanHandPoseObservation.JointName) -> CGPoint? { guard let p = points[joint], p.confidence > 0.25 else { return nil }; return p.location }
 tracked[slot].joints = points.filter { $0.value.confidence > 0.25 }.mapValues { CGPoint(x:$0.location.x,y:1-$0.location.y) }
 guard let wrist = p(.wrist),let middle = p(.middleMCP) else { continue }
 // Keep the previous wrist even through occlusion; never match against the orb position.
 if now-tracked[slot].lastSeen < 0.5 && cost(observation,slot) > 0.28 { continue }
 tracked[slot].wrist = wrist
 tracked[slot].lastSeen = now
 tracked[slot].seen = true
 // Every element uses the same palm-local anchor, including lightning.
 let knuckles = [p(.indexMCP),p(.middleMCP),p(.ringMCP),p(.littleMCP)].compactMap { $0 }
 let knuckle = CGPoint(x:knuckles.map(\.x).reduce(0,+)/CGFloat(knuckles.count),y:knuckles.map(\.y).reduce(0,+)/CGFloat(knuckles.count))
 let target = CGPoint(x:wrist.x+(knuckle.x-wrist.x)*0.78,y:wrist.y+(knuckle.y-wrist.y)*0.78)
 let alpha: CGFloat = tracked[slot].power > 0.1 ? 0.28 : 1
 tracked[slot].center.x += (target.x-tracked[slot].center.x)*alpha
 tracked[slot].center.y += (target.y-tracked[slot].center.y)*alpha
 let targetPower: CGFloat = tracked[slot].closedFrames > 15 && !freezeShape ? 0 : 1
 tracked[slot].power += (targetPower-tracked[slot].power)*0.18
 guard let thumb = p(.thumbTip),let index = p(.indexTip) else { continue }
 func distance(_ a: CGPoint,_ b: CGPoint) -> CGFloat { hypot(a.x-b.x,(a.y-b.y)*9/16) }
 let scale = max(0.018,distance(wrist,middle))
 let tips: [VNHumanHandPoseObservation.JointName] = [.indexTip,.middleTip,.ringTip,.littleTip]
 guard tips.compactMap({p($0)}).count >= 3 else { continue }
 let extended = tips.compactMap { p($0) }.filter { distance($0,wrist) > scale*1.45 }.count
 let gap = distance(thumb,index)/scale
 let candidate = gap < 0.3 ? (playgroundOn ? tracked[slot].mode : 3) : extended == 1 ? 1 : extended == 2 ? 2 : 0
 if tracked[slot].candidate == candidate { tracked[slot].stableFrames += 1 } else { tracked[slot].candidate = candidate; tracked[slot].stableFrames = 0 }
 if tracked[slot].stableFrames >= 9 && !freezeShape { tracked[slot].mode = candidate }
 // Finger aperture controls size independently of distance to the camera.
 let radius = min(0.12,max(0.023,0.025+gap*0.031))
 if !freezeShape { tracked[slot].radius += (radius-tracked[slot].radius)*0.1 }
 tracked[slot].closedFrames = extended == 0 && gap > 0.3 ? tracked[slot].closedFrames+1 : 0

 tracked[slot].seen = true
 tracked[slot].trail.append(CGPoint(x:tracked[slot].center.x,y:1-tracked[slot].center.y))
 if tracked[slot].trail.count > 18 { tracked[slot].trail.removeFirst() }
 }
 for slot in 0..<2 where !tracked[slot].seen {
 if now-tracked[slot].lastSeen > 0.7 { tracked[slot].power *= 0.85 }; tracked[slot].joints = [:]
 tracked[slot].trail = Array(tracked[slot].trail.dropFirst())
 }
 } catch {
 cachedYaw=nil
 for slot in 0..<2 { tracked[slot].seen = false; if now-tracked[slot].lastSeen > 0.7 { tracked[slot].power *= 0.85 }; tracked[slot].joints = [:] }
 }
 guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
 let snapshot = tracked
 let fusion = fusionHold.update(snapshot,now:now)
 let visualHands = snapshot.map { hand -> HandEnergy in
 var hand = hand
 if !energyOn { hand.power = 0 }
 if playgroundOn,let thumb = hand.joints[.thumbTip],let index = hand.joints[.indexTip],hypot(thumb.x-index.x,(thumb.y-index.y)*9/16) < 0.04 { hand.power = 0 }
 return hand
 }
 let visualFusion = Fusion(center:fusion.center,radius:fusion.radius,amount:energyOn && visualHands.allSatisfy { $0.power > 0.1 } ? fusion.amount : 0,mode:fusion.mode,label:fusion.label)
 let image: CGImage?
 if energyOn { image = renderer.render(buffer,hands:visualHands,fusion:visualFusion) }
 else { let cameraImage = CIImage(cvPixelBuffer:buffer).transformed(by:CGAffineTransform(scaleX:0.5,y:0.5));image = renderer.context.createCGImage(cameraImage,from:cameraImage.extent) }
 let active = snapshot.filter { $0.power > 0.25 }
 let text: String
 if fusion.amount > 0.5 {
 let ratio = max(snapshot[0].radius,snapshot[1].radius)/max(0.01,min(snapshot[0].radius,snapshot[1].radius))
 text = "FUSION · \(fusion.label) · \(ratio > 1.6 ? "dominant core" : "balanced core") · separate hands to split"
 } else if active.isEmpty { text = "Show one or both hands · open fingers to grow energy" }
 else { text = active.map { "\(Fusion.names[$0.mode]) \(Int($0.radius/0.12*100))%" }.joined(separator:"  +  ") + " · bring energy together to fuse" }
 let yaw = now-lastFaceAt < 0.12 ? cachedYaw:nil
 DispatchQueue.main.async { guard CFAbsoluteTimeGetCurrent()-now < 0.12 else { return };self.headYaw=yaw;self.frameStarted = now;self.hands = snapshot; self.fusionAmount = fusion.amount; self.frame = image; self.status = text }
 }
}
final class Relighter {
 let context = CIContext(options: [.cacheIntermediates: false])
 let kernel = CIKernel(source: """
 kernel vec4 prism(sampler video, vec2 center, float radius, float time, float power, float mode) {
 vec2 xy = destCoord();
 vec2 d = (xy-center)/radius;
 float r = length(d);
 float a = atan(d.y,d.x);
 float turbulence = sin(a*7.0+time*2.0+r*9.0)*0.5 + sin(a*13.0-time*3.0-r*5.0)*0.25;
 vec2 offset = normalize(d+vec2(0.001)) * sin(r*14.0-time*4.0)*3.0*exp(-r*0.7)*power;
 vec4 base = sample(video, samplerTransform(video,xy+offset));
 vec3 tint = vec3(0.08,0.55,1.0);
 if (mode > 1.5 && mode < 2.5) { tint = vec3(1.0,0.21,0.035); }
 if (mode > 2.5 && mode < 3.5) { tint = vec3(0.52,0.12,1.0); }
 float spill = exp(-r*r*0.075)*power;
 vec3 lit = base.rgb*(0.84+0.65*spill*tint) + base.rgb*tint*spill*0.7;
 float shell = exp(-pow((r-0.82-turbulence*0.055)*15.0,2.0));
 float inner = exp(-r*r*4.0)*(0.55+0.35*sin(r*19.0-time*3.0+a*4.0));
 float filaments = pow(max(0.0,sin(a*9.0+r*18.0+time*3.0+turbulence)),18.0)*exp(-r*r*0.9);
 float glow = exp(-r*r*0.8)*0.22;
 float light = shell*2.2+inner*2.8+filaments*1.5+glow;
 if (mode > 0.5 && mode < 1.5) {
  float bolt = abs(d.x - 0.15*sin(d.y*17.0+time*8.0) - 0.08*sin(d.y*43.0-time*14.0));
  light = exp(-bolt*65.0)*exp(-abs(d.y)*0.35)*2.7+exp(-bolt*8.0)*0.3;
 }
 if (mode > 1.5 && mode < 2.5) {
  float ring = abs(r-1.35-0.04*sin(a*31.0+time*9.0));
  light = exp(-ring*48.0)*2.4+exp(-ring*7.0)*0.3;
  lit *= 1.0-0.6*exp(-r*r*2.0)*power;
 }
 if (mode > 2.5 && mode < 3.5) {
  light = exp(-abs(r-0.65)*38.0)*2.0 + exp(-abs(d.y+sin(d.x*4.0+time)*0.07)*35.0)*exp(-abs(d.x))*0.8;
  lit *= 1.0-0.98*exp(-pow(r/0.6,6.0))*power;
 }
 if (mode > 3.5) {
 float kind = mode-4.0;
 tint = 0.45+0.45*cos(vec3(0.0,2.1,4.2)+kind*0.78);
 float warp = sin(a*(5.0+mod(kind,4.0))+time*3.0+r*7.0);
 float ring = exp(-abs(r-1.05-warp*0.08)*28.0);
 float spiral = pow(max(0.0,sin(a*(3.0+mod(kind,3.0))+r*15.0-time*4.0)),12.0)*exp(-r*r*0.8);
 light = ring*2.8+spiral*2.0+exp(-r*r*3.0)*1.8+glow;
 if (mode == 7.0 || mode == 10.0 || mode == 12.0 || mode == 13.0) {
 lit *= 1.0-0.95*exp(-pow(r/0.65,6.0))*power;
 light *= 1.0-exp(-pow(r/0.6,6.0));
 }
 }
 vec3 effect = tint*light + vec3(0.75,0.87,1.0)*max(0.0,light-1.1);
 vec3 mapped = 1.0-exp(-(lit+effect*power));
 return vec4(mix(base.rgb,mapped,clamp(power*2.0,0.0,1.0)),1.0);
 }
 """)!
 func render(_ buffer: CVPixelBuffer,hands:[HandEnergy],fusion:Fusion) -> CGImage? {
 var image = CIImage(cvPixelBuffer:buffer)
 let extent = image.extent
 let time = CFAbsoluteTimeGetCurrent().truncatingRemainder(dividingBy:1000)
 func apply(center:CGPoint,radius:CGFloat,power:CGFloat,mode:Int) {
 guard power > 0.015 else { return }
 let c = CIVector(x:center.x*extent.width,y:center.y*extent.height)
 if let output = kernel.apply(extent:extent,roiCallback:{ _, r in r.insetBy(dx:-20,dy:-20) },arguments:[image,c,extent.width*radius,time,power,mode]) { image = output }
 }
 for hand in hands { apply(center:hand.center,radius:hand.radius,power:hand.power*(1-fusion.amount),mode:hand.mode) }
 apply(center:fusion.center,radius:fusion.radius,power:fusion.amount,mode:fusion.mode)
 return context.createCGImage(image,from:extent)
 }

}
struct MotionTrail: View {
 let points: [CGPoint]; let mirrored: Bool; let power: CGFloat
 var body: some View {
 Canvas { context,size in
 guard points.count > 2 else { return }
 context.blendMode = .plusLighter
 for i in 1..<points.count {
 let a = points[i-1], b = points[i]
 var path = Path()
 path.move(to:CGPoint(x:(mirrored ? 1-a.x : a.x)*size.width,y:a.y*size.height))
 path.addLine(to:CGPoint(x:(mirrored ? 1-b.x : b.x)*size.width,y:b.y*size.height))
 let age = Double(i)/Double(points.count)
 context.stroke(path,with:.color(.cyan.opacity(age*Double(power)*0.5)),style:StrokeStyle(lineWidth:age*8,lineCap:.round))
 }
 }.allowsHitTesting(false)
 }
}

struct HandOverlay: View {
 typealias Joint = VNHumanHandPoseObservation.JointName
 let joints: [Joint: CGPoint]
 let mirrored: Bool
 static let chains: [[Joint]] = [
 [.wrist,.thumbCMC,.thumbMP,.thumbIP,.thumbTip],
 [.wrist,.indexMCP,.indexPIP,.indexDIP,.indexTip],
 [.wrist,.middleMCP,.middlePIP,.middleDIP,.middleTip],
 [.wrist,.ringMCP,.ringPIP,.ringDIP,.ringTip],
 [.wrist,.littleMCP,.littlePIP,.littleDIP,.littleTip]]
 static let names = ["THUMB","INDEX","MIDDLE","RING","LITTLE"]
 var body: some View {
 Canvas { ctx,size in
 let w = min(size.width,size.height*16/9), h = w*9/16
 let origin = CGPoint(x:(size.width-w)/2,y:(size.height-h)/2)
 func mapped(_ p: CGPoint) -> CGPoint { CGPoint(x:origin.x+(mirrored ? 1-p.x : p.x)*w,y:origin.y+p.y*h) }
 let color = Color.green
 let palm: [Joint] = [.wrist,.thumbCMC,.indexMCP,.middleMCP,.ringMCP,.littleMCP]
 // A translucent palm patch and a skeleton, not a pixel segmentation mask.
 if palm.allSatisfy({ joints[$0] != nil }) {
 var path = Path()
 for (i,joint) in palm.enumerated() { let p = mapped(joints[joint]!); if i == 0 { path.move(to:p) } else { path.addLine(to:p) } }
 path.closeSubpath(); ctx.fill(path,with:.color(color.opacity(0.12)))
 ctx.stroke(path,with:.color(color.opacity(0.5)),lineWidth:1)
 }
 for (index,chain) in Self.chains.enumerated() {
 for i in 1..<chain.count {
 if let a = joints[chain[i-1]], let b = joints[chain[i]] {
 var path = Path();path.move(to:mapped(a));path.addLine(to:mapped(b))
 ctx.stroke(path,with:.color(.black.opacity(0.8)),lineWidth:4)
 ctx.stroke(path,with:.color(color.opacity(0.9)),lineWidth:1.5)
 }
 }
 if let tip = joints[chain.last!] {
 let p = mapped(tip)
 let text = Text(Self.names[index]).font(.system(size:9,weight:.bold,design:.monospaced)).foregroundColor(.green)
 ctx.draw(text,at:CGPoint(x:p.x,y:p.y-15),anchor:.bottom)
 }
 }
 for (joint,point) in joints {
 let p = mapped(point)
 let isTip = Self.chains.contains { $0.last == joint }
 let radius: CGFloat = isTip ? 5 : 3
 let rect = CGRect(x:p.x-radius,y:p.y-radius,width:radius*2,height:radius*2)
 ctx.fill(Path(ellipseIn:rect),with:.color(.black.opacity(0.8)))
 ctx.stroke(Path(ellipseIn:rect),with:.color(isTip ? .white : color),lineWidth:1.5)
 }
 }.allowsHitTesting(false).accessibilityLabel("Live hand joint tracking overlay")
 }
}

struct GestureLab: View {
 @ObservedObject var camera: Camera
 @ObservedObject var world: Playground
 let close: () -> Void
 var body: some View {
 VStack(spacing:0) {
 HStack { Text("PRISM").font(.system(size:17,weight:.medium,design:.monospaced)).tracking(6); Button("Back to Studio",action:close); Text("GESTURE LAB").font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary); Spacer(); Circle().fill(camera.running ? .green : .gray).frame(width:6,height:6); Text(camera.running ? "LIVE · ON DEVICE" : "CAMERA OFF").font(.system(size:10,design:.monospaced)) }.padding(22)
 ZStack {
 Color.black
 if let frame = camera.frame, camera.running {
 Image(decorative: frame, scale: 1).resizable().aspectRatio(contentMode:.fit).scaleEffect(x:camera.mirrored ? -1 : 1,y:1)
 }
 if !camera.running && !world.enabled { VStack(spacing:14) { Image(systemName:"sparkle").font(.system(size:34)).foregroundStyle(.cyan); Text("Light at your fingertips.").font(.system(size:30,weight:.light)); Text("Two hands. Two elements. Bring them together.").foregroundStyle(.secondary) } }
 PlaygroundView(world:world,hands:camera.hands,mirrored:camera.mirrored,running:camera.running).opacity(world.enabled ? 1 : 0).allowsHitTesting(false)
 if camera.running,world.enabled,let frame = camera.frame {
 Canvas { context,size in
 let w = min(size.width,size.height*16/9), h = w*9/16
 let rect = CGRect(x:(size.width-w)/2,y:(size.height-h)/2,width:w,height:h)
 for slot in 0..<2 where world.foregroundHands[slot] {
 let joints = camera.hands[slot].joints
 func point(_ p:CGPoint) -> CGPoint { CGPoint(x:rect.minX+(camera.mirrored ? 1-p.x : p.x)*w,y:rect.minY+p.y*h) }
 guard let wrist = joints[.wrist],let middle = joints[.middleMCP] else { continue }
 let a = point(wrist), b = point(middle), span = hypot(a.x-b.x,a.y-b.y)
 var mask = Path()
 let palm = [.wrist,.thumbCMC,.indexMCP,.middleMCP,.ringMCP,.littleMCP].compactMap { (j:VNHumanHandPoseObservation.JointName) in joints[j].map(point) }
 if let first = palm.first { mask.move(to:first);for p in palm.dropFirst() { mask.addLine(to:p) };mask.closeSubpath() }
 for chain in HandOverlay.chains {
 for i in 1..<chain.count {
 guard let start = joints[chain[i-1]],let end = joints[chain[i]] else { continue }
 var segment = Path();segment.move(to:point(start));segment.addLine(to:point(end))
 mask.addPath(segment.strokedPath(StrokeStyle(lineWidth:max(5,span*0.22),lineCap:.round)))
 }
 }
 var layer = context
 layer.clip(to:mask)
 if camera.mirrored { layer.translateBy(x:size.width,y:0);layer.scaleBy(x:-1,y:1) }
 layer.draw(Image(decorative:frame,scale:1),in:rect)
 }
 }.allowsHitTesting(false)
 }
 if camera.running {
 ForEach(0..<2,id: \.self) { slot in
 if camera.energyOn { MotionTrail(points:camera.hands[slot].trail,mirrored:camera.mirrored,power:camera.hands[slot].power*(1-camera.fusionAmount)) }
 if camera.showTracking { HandOverlay(joints:camera.hands[slot].joints,mirrored:camera.mirrored) }
 }
 }
 if world.enabled && world.orbitMode {
 VStack { Text("PINCH + DRAG   ↔ TURN   ↕ TILT   ·   RELEASE TO REGRIP").font(.system(size:12,weight:.medium,design:.monospaced)).padding(12).background(.black.opacity(0.7)).clipShape(Capsule()).padding(18);Spacer() }.allowsHitTesting(false)
 }
 VStack { Spacer(); HStack { Text(world.enabled ? world.message : camera.status).font(.system(size:11,design:.monospaced)).padding(12).background(.black.opacity(0.6)).clipShape(Capsule()); Spacer() }.padding(22) }
 }.aspectRatio(16/9,contentMode:.fit).clipped()
 HStack(spacing:16) {
 Toggle("3D playground",isOn:$world.enabled).onChange(of:world.enabled) { camera.playgroundOn = world.enabled }
 Toggle("Virtual table",isOn:$world.tableOn)
 Toggle("Inspect / orbit",isOn:$world.orbitMode)
 Toggle("Energy + fusion",isOn:$camera.energyOn)
 Menu("Add world") { ForEach(["Island","Ocean","Galaxy","Storm"],id:\.self) { kind in Button(kind) { world.spawn(kind) } } }
 Menu("Weather: \(world.weather)") { ForEach(["Sunny","Sunset","Storm"],id:\.self) { weather in Button(weather) { world.weather = weather;world.setWeather() } } }
 Button("Explode") { world.explodeIsland() }
 Button("Rebuild") { world.rebuildIsland() }
 Button("Reset") { world.reset() }
 Spacer()
 EmptyView()
 }.padding(.horizontal,22).padding(.top,12)
 HStack(spacing:12) {
 VStack(alignment:.leading,spacing:5) { Text(world.enabled ? "PINCH · GRAB    FIST · PUNCH    OPEN PALM + FIST · HAMMER" : "PALM · PLASMA   POINT · LIGHTNING   V · PORTAL   PINCH · VOID").font(.system(size:10,design:.monospaced)); Text("Spread fingers to grow · bring together to fuse · pull apart to split").font(.system(size:11)).foregroundStyle(.secondary) }; Spacer()
 Toggle("Hand tracking",isOn:$camera.showTracking).toggleStyle(.checkbox)
 Toggle("Follow my movement",isOn:$camera.mirrored).toggleStyle(.checkbox)
 Button(camera.running ? "Stop camera" : "Start camera") { if camera.running { camera.stop() } else { camera.demo = false; camera.start() } }.buttonStyle(.borderedProminent).tint(.blue)
 }.padding(22)
 }.background(Color(red:0.045,green:0.055,blue:0.065)).preferredColorScheme(.dark).frame(minWidth:1280,minHeight:800)
 }
}
struct Content: View {
 @StateObject var camera = Camera()
 @StateObject var world = Playground()
 @StateObject var studio = StudioState()
 var body: some View {
 Group {
 if studio.lab {
 GestureLab(camera:camera,world:world,close:{
 if camera.running { camera.stop() }
 studio.lab = false
 })
 } else { IslandStudio(state:studio,world:world) }
 }.preferredColorScheme(.dark).frame(minWidth:1000,minHeight:650)
 }
}
final class Delegate: NSObject, NSApplicationDelegate {
 var window: NSWindow!
 func applicationDidFinishLaunching(_ notification: Notification) {
 window = NSWindow(contentRect:NSRect(x:0,y:0,width:1120,height:780),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
 window.title = "Prism Craft"; window.contentView = NSHostingView(rootView:CraftPractice()); window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
 }
 func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let delegate = Delegate()
app.setActivationPolicy(.regular)
app.delegate = delegate
let menu = NSMenu(); let item = NSMenuItem(); menu.addItem(item); let sub = NSMenu(); sub.addItem(withTitle:"Quit Prism Craft",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q"); item.submenu = sub; app.mainMenu = menu
app.run()
