import Cocoa
import SceneKit

extension Playground {
 var island: SCNNode? { objects.first { $0.name == "Island" } }
 func explodeIsland() {
 guard let island,!exploded else { return }
 release(0);release(1);exploded = true;islandHealth = 0
 fragments = island.childNodes.map { ($0,$0.position,$0.rotation,$0.scale,$0.isHidden) }
 for (i,node) in island.childNodes.enumerated() {
 if node.name == "Weather" { node.isHidden = true;continue }
 let a = CGFloat(i)*2.39996
 let target = SCNVector3(node.position.x+cos(a)*1.6,node.position.y+sin(a*3)*1.2,node.position.z+sin(a)*1.6)
 node.runAction(.group([.move(to:target,duration:0.6),.rotateBy(x:CGFloat(i%3)*0.8,y:1.2,z:0.5,duration:0.6),.scale(to:0.7,duration:0.6)]),forKey:"shatter")
 }
 message = "SHATTERED · Rebuild puts every piece back"
 }
 func rebuildIsland() {
 for (node,position,rotation,scale,hidden) in fragments {
 node.removeAction(forKey:"shatter")
 SCNTransaction.begin();SCNTransaction.animationDuration = 0.6
 node.position = position;node.rotation = rotation;node.scale = scale;node.isHidden = hidden
 SCNTransaction.commit()
 }
 fragments = [];exploded = false;islandHealth = 100
 island?.childNode(withName:"Damage",recursively:false)?.removeFromParentNode()
 weatherApplied = "";setWeather()
 message = "REBUILT · the island is whole again"
 }
 func damageIsland() {
 guard let island,!exploded else { return }
 islandHealth = max(0,islandHealth-34)
 if islandHealth == 0 { explodeIsland();return }
 let mark = island.childNode(withName:"Damage",recursively:false) ?? SCNNode()
 mark.name = "Damage"
 if mark.parent == nil { island.addChildNode(mark) }
 let crack = SCNNode(geometry:SCNBox(width:0.025,height:0.012,length:1.7,chamferRadius:0))
 crack.position = SCNVector3(CGFloat(islandHealth%3)*0.18,0.285,0)
 crack.eulerAngles.y = CGFloat(islandHealth)*0.03
 crack.geometry!.firstMaterial!.diffuse.contents = NSColor(white:0.12,alpha:1);mark.addChildNode(crack)
 island.runAction(.sequence([.moveBy(x:0.04,y:0,z:0,duration:0.04),.moveBy(x:-0.08,y:0,z:0,duration:0.06),.moveBy(x:0.04,y:0,z:0,duration:0.04)]),forKey:"impact")
 message = "CRACK · island integrity \(islandHealth)%"
 }
 func expandIsland(animated: Bool = true, terrain: String = "Woodland") {
 guard let island,!exploded else { return }
 expansions += 1
 let side: CGFloat = expansions%2 == 1 ? 1 : -1
 let step = CGFloat((expansions+1)/2)
 let x = side*(1.5+step-0.5)
 let tile = SCNNode();tile.name = "Expansion:"+terrain
 let rock = SCNNode(geometry:SCNBox(width:1,height:0.65,length:2.4,chamferRadius:0.035))
 rock.position.y = -0.2;rock.geometry!.firstMaterial!.diffuse.contents = NSColor(red:0.32,green:0.22,blue:0.15,alpha:1)
 let grass = SCNNode(geometry:SCNBox(width:1,height:0.14,length:2.3,chamferRadius:0.02))
 grass.position.y = 0.2;grass.geometry!.firstMaterial!.diffuse.contents = NSColor(red:0.32,green:0.57,blue:0.24,alpha:1)
 tile.addChildNode(rock);tile.addChildNode(grass)
 let tree = SCNNode(geometry:SCNCone(topRadius:0,bottomRadius:0.22,height:0.6))
 (tree.geometry as? SCNCone)?.radialSegmentCount = 7
 tree.position = SCNVector3(0,0.56,-0.5);tree.geometry!.firstMaterial!.diffuse.contents = NSColor(red:0.12,green:0.35,blue:0.18,alpha:1)
 if terrain == "Woodland" { tile.addChildNode(tree) }
 else if terrain == "Pond" {
 let water = SCNNode(geometry:SCNCylinder(radius:0.37,height:0.03))
 water.position = SCNVector3(0,0.29,0);water.scale.z = 1.65
 water.geometry?.firstMaterial?.diffuse.contents = NSColor(red:0.12,green:0.56,blue:0.7,alpha:1)
 tile.addChildNode(water)
 } else {
 for i in 0..<5 {
 let flower = SCNNode(geometry:SCNSphere(radius:0.045))
 flower.position = SCNVector3(sin(CGFloat(i)*2.4)*0.28,0.31,CGFloat(i-2)*0.29)
 flower.geometry?.firstMaterial?.diffuse.contents = i%2 == 0 ? NSColor.systemYellow : NSColor.systemPink
 tile.addChildNode(flower)
 }
 }
 tile.position = SCNVector3(x,0,0);tile.scale = SCNVector3(0.1,0.1,0.1)
 island.addChildNode(tile);if animated { tile.runAction(.scale(to:1,duration:0.25)) } else { tile.scale = SCNVector3(1,1,1) }
 message = "HAMMER · new land built · \(expansions) expansions"
 }
 func prepareHammer() {
 guard hammer.parent == nil else { return }
 let handle = SCNNode(geometry:SCNCylinder(radius:0.045,height:0.7));handle.position.y = -0.1
 handle.geometry!.firstMaterial!.diffuse.contents = NSColor(red:0.47,green:0.25,blue:0.12,alpha:1)
 let head = SCNNode(geometry:SCNBox(width:0.55,height:0.22,length:0.25,chamferRadius:0.04));head.position.y = 0.26
 head.geometry!.firstMaterial!.diffuse.contents = NSColor(white:0.55,alpha:1)
 hammer.addChildNode(handle);hammer.addChildNode(head);scene.rootNode.addChildNode(hammer)
 }
 func fistClosed(_ hand:HandEnergy,wrist:CGPoint,middle:CGPoint) -> Bool {
 let size = max(0.02,hypot(wrist.x-middle.x,(wrist.y-middle.y)*9/16))
 let tips = [hand.joints[.indexTip],hand.joints[.middleTip],hand.joints[.ringTip],hand.joints[.littleTip]].compactMap { $0 }
 return tips.count == 4 && tips.allSatisfy { hypot($0.x-wrist.x,($0.y-wrist.y)*9/16) <= size*1.4 }
 }
 func updateTools(hands:[HandEnergy],signals:[GrabSignal],mirrored:Bool,now:Double) {
 let dt = max(0.01,min(0.15,now-toolTime));toolTime = now
 hammer.isHidden = tool != "Hammer"
 if tool == "Hammer" { prepareHammer();hammer.isHidden = true }
 for slot in 0..<2 {
 guard hands[slot].seen else { toolPrevious[slot] = nil;continue }
 let hand = hands[slot]
 let raw = hand.joints[.wrist]
 let point = raw.map { CGPoint(x:mirrored ? 1-$0.x : $0.x,y:$0.y) }
 guard let point else { continue }
 let previous = toolPrevious[slot] ?? point;toolPrevious[slot] = point
 let speed = (point.y-previous.y)/dt
 let input = GrabSignal(valid:true,point:point)
 let near = nearest(input)?.name == "Island"
 if tool == "Hammer", let wrist = raw, let middle = hand.joints[.middleMCP], fistClosed(hand,wrist:wrist,middle:middle) {
 hammer.isHidden = false;hammer.position = worldPoint(input,z:island?.position.z ?? 1)
 hammer.eulerAngles.z = -0.4
 if near,speed > 0.28,now-lastStrike > 0.65 { lastStrike = now;expandIsland();return }
 }
 if tool == "Punch",let wrist = hand.joints[.wrist],let middle = hand.joints[.middleMCP] {
 let closed = fistClosed(hand,wrist:wrist,middle:middle)
 if closed,near,speed > 0.3,now-lastStrike > 0.65 { lastStrike = now;damageIsland();return }
 }
 }
 if now-lastStrike > 1.5 {
 message = tool == "Hammer" ? "HAMMER · keep one palm open · strike down with the fist to build land" : "PUNCH · close a fist and strike down over the island · Rebuild repairs it"
 }
 }
}
