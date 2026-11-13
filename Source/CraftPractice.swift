import Cocoa
import SwiftUI
import Vision

struct CraftInput {
 var move = CGVector.zero
 var look = CGVector.zero
 var mine = false
 var sprint = false
 var sneak = false
 var pause = false
 var drop = false
 var view = false
 var hotbarPreview: Int?
 var wheel = false
 var place = false
 var jump = false
 var inventory = false
 var slot = 0
 var cursor: CGPoint?
 var pinched = false
}
struct CraftGestures {
 var leftSlot: Int?
 var centers = [CGPoint.zero,CGPoint.zero]
 var sizes:[CGFloat] = [0.06,0.06]
 var wheelSizes:[CGFloat]?
 var wheelAngle:CGFloat?
 var wheelRatio:CGFloat = 1
 var wheelDrive:CGFloat = 0
 var wheelSprint = false
 var leftGrip=false,rightGrip=false
 var leftReady=false,rightReady=false
 var aimWasHeld=false
 var jumpClosed = false
 var useClosed = false
 var cursorClosed = false
 var jumpReady = false
 var useReady = false
 var extraSince:[Double?] = [nil,nil]
 var extraFired = [false,false]
 var pauseSince:Double?
 var pauseFired=false
 var thumbSince:Double?
 var inventoryFired = false
 var thumbReleasedAt:Double?
 var previous: CGPoint?
 var previousAt = 0.0
 var fistSince:Double?
 var placeSince:Double?
 var hotbarCandidate = 0
 var hotbarSince = 0.0
 var hotbarOpenSince:Double?
 var hotbarUntil = 0.0
 var hotbarCooldown = 0.0
 var wheelTilt:CGFloat = 0
 func visible(_ h:HandEnergy) -> Bool { h.seen && h.joints[.wrist] != nil && h.joints[.middleMCP] != nil }
 func point(_ h:HandEnergy) -> CGPoint { let p=h.joints[.wrist] ?? .zero;return CGPoint(x:1-p.x,y:p.y) }
 func distance(_ a:CGPoint,_ b:CGPoint) -> CGFloat { hypot(a.x-b.x,(a.y-b.y)*9/16) }
 func size(_ h:HandEnergy) -> CGFloat {
 guard let a=h.joints[.wrist],let b=h.joints[.middleMCP] else { return 0.06 }
 let span = h.joints[.indexMCP].flatMap { i in h.joints[.littleMCP].map { distance(i,$0)*0.9 } } ?? 0
 return max(0.02,distance(a,b),span)
 }
 func gap(_ h:HandEnergy,_ tip:VNHumanHandPoseObservation.JointName) -> CGFloat? {
 guard let a=h.joints[.thumbTip],let b=h.joints[tip] else { return nil };return distance(a,b)/size(h)
 }
 func fingers(_ h:HandEnergy) -> Int? {
 guard let w=h.joints[.wrist] else { return nil }
 let tips:[VNHumanHandPoseObservation.JointName] = [.indexTip,.middleTip,.ringTip,.littleTip]
 let points=tips.compactMap { h.joints[$0] }
 guard points.count == 4 else { return nil }
 return points.filter { distance(w,$0)>size(h)*1.45 }.count
 }
 func digitCount(_ h:HandEnergy) -> Int? {
 guard visible(h),let fingers=fingers(h),let thumb=h.joints[.thumbTip],let index=h.joints[.indexMCP] else { return nil }
 let openThumb = distance(thumb,index)>size(h)*0.83
 return fingers+(openThumb ? 1:0)
 }
 mutating func calibrate(_ hands:[HandEnergy]) -> Bool {
 guard hands.count == 2,hands.allSatisfy(visible) else { return false }
 let p=hands.map(point)
 guard abs(p[0].x-p[1].x)>0.12 else { return false }
 self=CraftGestures()
 centers=p;sizes=hands.map(size);leftSlot=p[0].x<p[1].x ? 0:1
 return true
 }
 func axis(_ x:CGFloat,dead:CGFloat) -> CGFloat {
 let t=min(1,max(0,(abs(x)-dead)/(0.17-dead)));return x<0 ? -t:t
 }
 mutating func step(_ hands:[HandEnergy], inventoryMode:Bool,now:Double) -> CraftInput {
 guard hands.count == 2 else { return CraftInput() }
 if leftSlot == nil { _=calibrate(hands) }
 let available = hands.firstIndex(where:visible) ?? 0
 let left=leftSlot ?? (point(hands[available]).x < 0.5 ? available : 1-available)
 let right=1-left
 let l=hands[left],r=hands[right]
 var out=CraftInput()
 // Deliberate menu gesture: left V plus right open palm, held once.
 let pausePose=hotbarUntil<=now && wheelSizes == nil && visible(l) && visible(r) && digitCount(l)==2 && digitCount(r)==5 && (gap(l,.indexTip) ?? 0)>0.65 && (gap(r,.indexTip) ?? 0)>0.65
 if pausePose {
 if pauseSince == nil { pauseSince=now }
 if !pauseFired && now-(pauseSince ?? now)>=0.7 { out.pause=true;pauseFired=true }
 return out
 } else { pauseSince=nil;pauseFired=false }
 let thumbUp:Bool = {
 guard visible(l),fingers(l)==0,let wrist=l.joints[.wrist],let thumb=l.joints[.thumbTip],let middle=l.joints[.middleMCP] else { return false }
 return (wrist.y-thumb.y)*9/16>size(l)*1.15 && (middle.y-thumb.y)*9/16>size(l)*0.17
   && abs(thumb.x-wrist.x)<size(l)*0.8
 }()
 if thumbUp && (gap(l,.indexTip) ?? 0)>0.65 && (inventoryMode || (!rightGrip && wheelSizes == nil)) {
 thumbReleasedAt=nil
 if thumbSince == nil { thumbSince=now }
 if !inventoryFired,now-(thumbSince ?? now)>=0.45 { out.inventory=true;inventoryFired=true }
 leftGrip=false;leftReady=false;previous=nil;aimWasHeld=false;fistSince=nil;placeSince=nil
 return out
 } else {
 thumbSince=nil
 if thumbReleasedAt == nil { thumbReleasedAt=now }
 if now-(thumbReleasedAt ?? now)>0.2 { inventoryFired=false }
 }
 if inventoryMode {
 previous=nil;aimWasHeld=false;wheelSizes=nil;wheelAngle=nil;leftReady=false;rightReady=false;leftGrip=false;rightGrip=false;fistSince=nil;placeSince=nil
 let h=visible(r) ? r:l
 guard visible(h),let index=h.joints[.indexTip],let thumb=h.joints[.thumbTip] else { cursorClosed=false;return out }
 let gap=distance(index,thumb)/size(h)
 if gap<0.43 { cursorClosed=true };if gap>0.66 { cursorClosed=false }
 let x=1-(index.x+thumb.x)/2,y=(index.y+thumb.y)/2
 out.cursor=CGPoint(x:min(1,max(0,(x-0.14)/0.72)),y:min(1,max(0,(y-0.12)/0.76)))
 out.pinched=cursorClosed
 out.sneak=visible(l) && fingers(l)==0
 if let m=self.gap(h,.middleTip),let i=self.gap(h,.indexTip) {
 if m>0.68 { useReady=true;useClosed=false }
 if m<0.43 && i>0.63 && useReady && !useClosed { out.place=true;useClosed=true;useReady=false }
 } else { useReady=false;useClosed=false }
 return out
 }
 cursorClosed=false
 if hotbarUntil>now {
 let a=digitCount(l),b=digitCount(r)
 let valid=(!visible(l) || a != nil) && (!visible(r) || b != nil)
 let count=valid ? (a ?? 0)+(b ?? 0):0
 let choice=(1...9).contains(count) ? count:0
 out.hotbarPreview=choice
 if choice != hotbarCandidate { hotbarCandidate=choice;hotbarSince=now }
 if choice>0,now-hotbarSince>=0.55 { out.slot=choice;hotbarUntil=0;hotbarCooldown=now+1.0;out.hotbarPreview=nil }
 leftGrip=false;rightGrip=false;leftReady=false;rightReady=false;aimWasHeld=false;previous=nil
 return out
 }
 if wheelSizes == nil && !leftGrip && !rightGrip && now>hotbarCooldown && digitCount(l)==5 && digitCount(r)==5 {
 if hotbarOpenSince == nil { hotbarOpenSince=now }
 if now-(hotbarOpenSince ?? now)>=0.6 {
 hotbarUntil=now+5;hotbarCandidate=0;hotbarOpenSince=nil;out.hotbarPreview=0;return out
 }
 } else { hotbarOpenSince=nil }
 func grip(_ hand:HandEnergy,_ held:Bool,_ ready:Bool) -> (Bool,Bool) {
 guard visible(hand),let g=gap(hand,.indexTip) else { return (false,false) }
 if g>0.63 { return (false,true) }
 if g<0.43 && ready { return (true,true) }
 return (held,ready)
 }
 let compactFist:Bool = {
 guard visible(r),fingers(r)==0,let w=r.joints[.wrist],let i=r.joints[.indexTip] else { return false }
 return distance(w,i)/size(r)<1.23
 }()
 (leftGrip,leftReady)=grip(l,leftGrip,leftReady)
 (rightGrip,rightReady)=grip(r,rightGrip,rightReady)
 if compactFist && !aimWasHeld && !leftGrip { rightGrip=false;rightReady=false }

 // Pinky pinches are held deliberately and exclude ordinary index/middle pinches.
 for (i,h) in [l,r].enumerated() {
 let pose=visible(h) && (gap(h,.littleTip) ?? 9)<0.43 && (gap(h,.indexTip) ?? 0)>0.7 && (gap(h,.middleTip) ?? 0)>0.65
 if pose && !leftGrip && !rightGrip {
 if extraSince[i] == nil { extraSince[i]=now }
 if !extraFired[i] && now-(extraSince[i] ?? now)>0.65 {
 if i==0 { out.drop=true } else { out.view=true };extraFired[i]=true
 }
 return out
 } else { extraSince[i]=nil;extraFired[i]=false }
 }
 if visible(l),!leftGrip,let g=gap(l,.middleTip),let index=gap(l,.indexTip) {
 if g>0.63 { jumpClosed=false;jumpReady=true }
 if g<0.4 && g+0.12<index && jumpReady && !jumpClosed { jumpClosed=true;jumpReady=false;out.jump=true }
 } else { jumpReady=false;jumpClosed=false }
 if leftGrip && rightGrip {
 out.wheel=true;hotbarOpenSince=nil;hotbarCooldown=now+0.7
 let lp=point(l),rp=point(r)
 let angle=atan2((rp.y-lp.y)*9/16,rp.x-lp.x)
 let separated=distance(lp,rp)>0.12
 if separated {
 if let start=wheelSizes,let old=wheelAngle,now-previousAt<0.12 {
 let ratio=(size(l)/start[0]+size(r)/start[1])/2
 wheelRatio += (ratio-wheelRatio)*0.45
 if wheelRatio>1.095 { wheelDrive=1 }
 else if wheelRatio<0.86 { wheelDrive = -1 }
 else if (wheelDrive>0 && wheelRatio<1.045) || (wheelDrive<0 && wheelRatio>0.92) { wheelDrive=0 }
 if wheelRatio>1.21 { wheelSprint=true }
 if wheelRatio<1.15 || wheelDrive != 1 { wheelSprint=false }
 out.move.dy=wheelDrive;out.sprint=wheelSprint
 let turn=atan2(sin(angle-old),cos(angle-old))
 wheelTilt += (turn-wheelTilt)*0.5
 let magnitude=min(0.55,max(0,(abs(wheelTilt)-0.095)*1.15))
 out.look.dx=wheelTilt<0 ? -magnitude:magnitude
 } else { wheelSizes=[size(l),size(r)];wheelAngle=angle;wheelTilt=0;wheelRatio=1;wheelDrive=0;wheelSprint=false }
 } else { wheelSizes=nil;wheelAngle=nil;wheelDrive=0;wheelSprint=false }
 previous=nil;previousAt=now;aimWasHeld=false;fistSince=nil;placeSince=nil
 return out
 }
 wheelSizes=nil;wheelAngle=nil;wheelRatio=1;wheelDrive=0;wheelSprint=false
 guard visible(r) else { previous=nil;aimWasHeld=false;fistSince=nil;placeSince=nil;useReady=false;hotbarCandidate=0;return out }
 let p=point(r)
 if let old=previous,now-previousAt<0.12,now-previousAt>0.009 {
 let dx=p.x-old.x,dy=p.y-old.y
 
 func delta(_ d:CGFloat,scale:CGFloat) -> CGFloat {
 if abs(d)<0.004 || abs(d)>0.14 { return 0 }
 return min(1,max(-1,d/scale))
 }
 if rightGrip && aimWasHeld { out.look=CGVector(dx:delta(dx,scale:0.045),dy:delta(dy,scale:0.065)) }
 }
 previous=p;previousAt=now;aimWasHeld=rightGrip
 out.sneak=visible(l) && fingers(l)==0 && !leftGrip
 if compactFist && !rightGrip && !leftGrip {
 if fistSince == nil { fistSince=now }
 out.mine=now-(fistSince ?? now)>=0.11
 } else { fistSince=nil }
 if let m=gap(r,.middleTip),let i=gap(r,.indexTip),!compactFist,!rightGrip,!leftGrip {
 if m>0.68 { useClosed=false;useReady=true;placeSince=nil }
 if m<0.52 && i>0.57 && m+0.18<i && useReady && !useClosed {
 if placeSince == nil { placeSince=now }
 if now-(placeSince ?? now)>=0.07 { out.place=true;useClosed=true;useReady=false;placeSince=nil }
 } else { placeSince=nil }
 } else { placeSince=nil;useReady=false }
 return out
 }
}
struct HeadSteering {
 var center:Double?
 var filtered = 0.0
 var needsNeutral = true
 mutating func calibrate(_ yaw:Double) { center=yaw;filtered=0;needsNeutral=false }
 mutating func turn(_ yaw:Double?,deadDegrees:Double,sensitivity:Double,invert:Bool) -> CGFloat {
 guard let yaw,let center,yaw.isFinite else { filtered=0;needsNeutral=true;return 0 }
 let dead=deadDegrees*Double.pi/180
 let d=yaw-center
 if abs(d)<=dead { filtered=0;needsNeutral=false;return 0 }
 if needsNeutral { return 0 }
 let span=max(0.12,0.49-dead)
 let amount=min(1,(abs(d)-dead)/span)
 let target=amount*min(0.9,max(0.15,sensitivity))*(d<0 ? -1:1)*(invert ? -1:1)
 filtered += (target-filtered)*0.55
 return CGFloat(filtered)
 }
}
final class CraftPracticeState: ObservableObject {
 var gestures = CraftGestures()
 var head = HeadSteering()
 @Published var headEnabled = true
 @Published var headDead = 9.0
 @Published var headSpeed = 0.65
 @Published var invertHead = false
 @Published var headStatus = "Center head before steering"
 var latestYaw:Double?
 func centerHead() {
 guard let latestYaw else { headStatus = "Face not detected · look toward the camera";return }
 head.calibrate(latestYaw);headStatus = "Centered · turn your head to steer"
 }

 @Published var input = CraftInput()
 @Published var player = CGPoint(x:0.5,y:0.5)
 @Published var aim = CGPoint(x:0.5,y:0.5)
 @Published var linked = false
 @Published var connection = "Minecraft bridge not detected"
 let bridge = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Prism Craft",isDirectory:true)
 let session = UUID().uuidString
 var lastWrite = 0.0
 var lastStatus = 0.0
 @Published var sentFrames = 0
 @Published var showJoints = false
 @Published var tracking = "0 hands tracked"
 var inventoryMode = false
 var inventoryCount = 0
 var pauseCount = 0
 var dropCount = 0
 var viewCount = 0
 func action(_ name:String) {
 switch name {
 case "inventory": inventoryCount += 1
 case "pause": pauseCount += 1
 case "drop": dropCount += 1
 case "view": viewCount += 1
 default: break
 }
 }
 var slot = 0
 @Published var jumps = 0
 @Published var placements = 0
 @Published var note = "Start the camera. Hold both hands apart and rest them where they feel comfortable."
 var last = ProcessInfo.processInfo.systemUptime
 func frame(_ hands:[HandEnergy],running:Bool,capturedAt:Double? = nil,headYaw:Double? = nil) {
 let now = ProcessInfo.processInfo.systemUptime
 if running, let capturedAt, CFAbsoluteTimeGetCurrent()-capturedAt > 0.12 { return }
 let dt = min(0.08,max(0,now-last));last = now
 if now-lastStatus > 0.4 {
 lastStatus = now
 let reply = (try? String(contentsOf:bridge.appendingPathComponent("status"),encoding:.utf8))?.split(separator:" ")
 if let reply,reply.count == 2,let time = Double(reply[0]),abs(Date().timeIntervalSince1970*1000-time) < 1600 {
 switch reply[1] {
 case "menu": inventoryMode = true; connection = "Menu linked · aim and pinch · V + palm to resume"
 case "inventory": inventoryMode = true; connection = "Inventory linked · aim and pinch"
 case "receiving": inventoryMode = false; connection = "Minecraft receiving controls"
 case "paused": inventoryMode = false;connection = "Minecraft paused or unfocused · return to game and press F8"
 case "armed": inventoryMode = false; connection = "Minecraft armed · waiting for camera controls"
 case "ready": inventoryMode = false; connection = "Minecraft connected · F8 in world to arm"
 default: inventoryMode = false; connection = "Minecraft bridge loaded · open a single-player world"
 }
 } else { inventoryMode = false;connection = "Minecraft bridge not detected" }
 }
 if !running { gestures = CraftGestures();head=HeadSteering() }
 latestYaw = running ? headYaw:nil
 let count = running ? hands.filter(gestures.visible).count : 0
 tracking = "\(count) / 2 hands tracked · "+(gestures.leftSlot == nil ? "show both hands to calibrate" : "calibrated")
 var next = running ? gestures.step(hands,inventoryMode:inventoryMode,now:now) : CraftInput()
 if headEnabled {
 let disabled=inventoryMode || next.inventory || next.hotbarPreview != nil
 next.look.dx=head.turn(disabled ? nil:latestYaw,deadDegrees:headDead,sensitivity:headSpeed,invert:invertHead)
 let message = head.center == nil ? "Center head before steering" : latestYaw == nil ? "Face not detected" : next.look.dx > 0.02 ? "Turning right" : next.look.dx < -0.02 ? "Turning left" : "Head steering neutral"
 if message != headStatus { headStatus=message }
 }
 input = next
 player.x = min(0.96,max(0.04,player.x+next.move.dx*dt*0.46))
 player.y = min(0.96,max(0.04,player.y-next.move.dy*dt*0.46))
 aim.x = min(0.94,max(0.06,aim.x+next.look.dx*dt*0.55))
 aim.y = min(0.94,max(0.06,aim.y+next.look.dy*dt*0.55))
 if next.jump { jumps += 1 };if next.place { placements += 1 }
 if next.drop { dropCount += 1 };if next.view { viewCount += 1 };if next.pause { pauseCount += 1 };if next.inventory { inventoryCount += 1 };if next.hotbarPreview != nil { slot = 0 };if next.slot > 0 { slot = next.slot }
 if linked && now-lastWrite >= 0.025 {
 lastWrite = now
 do {
 try FileManager.default.createDirectory(at:bridge,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
 let stamp = capturedAt.map { Int64(($0 + kCFAbsoluteTimeIntervalSince1970)*1000) } ?? Int64(Date().timeIntervalSince1970*1000)
 let message = "4 \(stamp) \(session) \(next.move.dx) \(next.move.dy) \(next.look.dx) \(next.look.dy) \(next.mine ? 1 : 0) \(jumps) \(placements) \(inventoryCount) \(slot) \(next.cursor?.x ?? -1) \(next.cursor?.y ?? -1) \(next.pinched ? 1 : 0) \(next.sprint ? 1 : 0) \(pauseCount) \(dropCount) \(viewCount) \(next.sneak ? 1 : 0)"
 try message.write(to:bridge.appendingPathComponent("controls"),atomically:true,encoding:.utf8);sentFrames += 1
 } catch { linked = false;note = "Couldn’t open the local connection." }
 }
 }
}
struct CraftPractice: View {
 @StateObject var camera = Camera()
 @StateObject var state = CraftPracticeState()
 var body: some View {
 VStack(alignment:.leading,spacing:18) {
 HStack {
 VStack(alignment:.leading,spacing:5) {
 Text("PRISM CRAFT").font(.system(size:11,weight:.semibold,design:.monospaced)).tracking(4).foregroundStyle(.mint)
 Text("Minecraft hand controls").font(.system(size:28,weight:.medium))
 }
 Spacer()
 Button(camera.running ? "Stop camera" : "Start camera") {
 if camera.running { camera.stop();state.gestures = CraftGestures();state.input = CraftInput() } else { camera.start() }
 }.buttonStyle(.borderedProminent).tint(.teal)
 Button("Set neutral position") {
 state.note = state.gestures.calibrate(camera.hands) ? "Calibrated. Return your hands to their starting positions to stop moving and looking." : "Show both hands, spaced apart, before setting neutral."
 }.disabled(!camera.running)
 }
 Text(!camera.running && camera.status != "Camera is off" ? camera.status : state.note).foregroundStyle(.secondary)
 Text(state.tracking).font(.callout).foregroundStyle(.mint)
 HStack(spacing:14) {
 Toggle("Head steering",isOn:$state.headEnabled)
 Button("Center head") { state.centerHead() }.disabled(!camera.running)
 Toggle("Reverse head turn",isOn:$state.invertHead)
 Text(state.headStatus).font(.caption).foregroundStyle(.secondary)
 Spacer()
 Menu("Head settings") {
 Button("Wider neutral range") { state.headDead=min(19,state.headDead+2) }
 Button("Narrower neutral range") { state.headDead=max(5,state.headDead-2) }
 Button("Slower turns") { state.headSpeed=max(0.15,state.headSpeed-0.1) }
 Button("Faster turns") { state.headSpeed=min(0.9,state.headSpeed+0.1) }
 Text("Neutral ±\(Int(state.headDead))° · Speed \(Int(state.headSpeed*100))%")
 }
 }
 HStack(spacing:16) {
 ZStack {
 Color.black
 if let frame = camera.frame,camera.running {
 Image(decorative:frame,scale:1).resizable().scaledToFit().scaleEffect(x:-1,y:1)
 if state.showJoints { ForEach(0..<2,id:\.self) { slot in HandOverlay(joints:camera.hands[slot].joints,mirrored:true) } }
 } else { Text("Camera preview").foregroundStyle(.secondary) }
 }.aspectRatio(16/9,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:12))
 ZStack {
 Color(red:0.08,green:0.15,blue:0.13)
 Canvas { context,size in
 for i in 0...12 {
 var line = Path();let x = CGFloat(i)*size.width/12, y = CGFloat(i)*size.height/12
 line.move(to:CGPoint(x:x,y:0));line.addLine(to:CGPoint(x:x,y:size.height))
 line.move(to:CGPoint(x:0,y:y));line.addLine(to:CGPoint(x:size.width,y:y))
 context.stroke(line,with:.color(.mint.opacity(0.13)),lineWidth:1)
 }
 let p = CGPoint(x:state.player.x*size.width,y:state.player.y*size.height)
 let a = CGPoint(x:state.aim.x*size.width,y:state.aim.y*size.height)
 context.fill(Path(roundedRect:CGRect(x:p.x-9,y:p.y-9,width:18,height:18),cornerRadius:3),with:.color(.mint))
 context.stroke(Path(ellipseIn:CGRect(x:a.x-9,y:a.y-9,width:18,height:18)),with:.color(state.input.mine ? .orange : .white),lineWidth:2)
 }.accessibilityLabel("Practice grid: square for movement, ring for aim")
 }.aspectRatio(16/9,contentMode:.fit).clipShape(RoundedRectangle(cornerRadius:12))
 }
 HStack(alignment:.top,spacing:28) {
 VStack(alignment:.leading,spacing:6) { Text("LEFT HAND").font(.headline);Text("Pinch both hands for the wheel.\nPush to walk; farther to sprint.\nPull back to reverse; release to stop.") }
 VStack(alignment:.leading,spacing:6) { Text("RIGHT HAND").font(.headline);Text("Turn your head to steer; pinch-drag for up/down.\nHold a right fist to mine; open to stop.\nRight thumb + middle places once.\nOpen both palms to arm hotbar, then show 1–9 fingers total.\nLeft thumbs-up: open / close inventory.\nLeft V + right palm held: pause / resume.\nLeft fist: crouch. Left thumb + middle: jump.\nHold left thumb + pinky: drop one item.\nHold right thumb + pinky: change camera view.") }
 Spacer()
 VStack(alignment:.leading,spacing:6) { Text(state.input.hotbarPreview.map { $0 == 0 ? "HOTBAR · SHOW 1–9 FINGERS" : "HOTBAR · HOLD \($0)" } ?? (state.input.mine ? "MINING" : state.input.sprint ? "SPRINTING" : state.input.move.dy > 0 ? "WALKING" : state.input.move.dy < 0 ? "REVERSING" : state.input.wheel ? "WHEEL ENGAGED" : "Idle")).foregroundStyle(state.input.mine ? .orange : .secondary);Text("Jumps: \(state.jumps)");Text("Places: \(state.placements)");Text("Inventory: \(state.inventoryCount) · Slot \(state.slot)") }
 }.font(.callout)
 HStack {
 Button("Inventory") { state.action("inventory") }
 Button("Pause / resume") { state.action("pause") }
 Button("Drop one item") { state.action("drop") }
 Button("Change camera view") { state.action("view") }
 Text("In menus: point with right hand; index pinch to click/drag; middle pinch to right-click; left fist for quick transfer.").font(.caption).foregroundStyle(.secondary)
 }
 Spacer()
 HStack { Toggle("Send to Minecraft",isOn:$state.linked);Toggle("Show hand joints",isOn:$state.showJoints);Text(state.connection);if state.linked { Text("Sent: \(state.sentFrames)") } }.font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary)
 }.padding(24).frame(minWidth:960,minHeight:610).preferredColorScheme(.dark)
 .onReceive(camera.$hands) { state.frame($0,running:camera.running,capturedAt:camera.frameStarted,headYaw:camera.headYaw) }
 .onReceive(Timer.publish(every:0.5,on:.main,in:.common).autoconnect()) { _ in if !camera.running { state.frame(camera.hands,running:false) } }
 }
}
