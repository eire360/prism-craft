import Cocoa
import Vision
import simd

// Planar palm fit. This estimates pose from perspective foreshortening; it is not a depth sensor.
enum PalmPose {
 static let model: [(VNHumanHandPoseObservation.JointName,SIMD2<Double>)] = [
 (.wrist,SIMD2(0,-1)),(.indexMCP,SIMD2(0.48,0.55)),(.middleMCP,SIMD2(0.1,0.78)),(.ringMCP,SIMD2(-0.25,0.67)),(.littleMCP,SIMD2(-0.52,0.38))]
 static func estimate(_ joints:[VNHumanHandPoseObservation.JointName:CGPoint],mirrored:Bool) -> simd_quatf? {
 var rows: [[Double]] = [];var targets:[Double] = []
 for (joint,p) in model {
 guard let image = joints[joint] else { return nil }
 let u = ((mirrored ? 1-image.x : image.x)-0.5)/1.2
 let v = (0.5-image.y)*9/16/1.2
 let x = p.x,y = p.y
 rows.append([x,y,1,0,0,0,-u*x,-u*y]);targets.append(u)
 rows.append([0,0,0,x,y,1,-v*x,-v*y]);targets.append(v)
 }
 var a = Array(repeating:Array(repeating:0.0,count:9),count:8)
 for i in 0..<8 { for j in 0..<8 { a[i][j] = rows.reduce(0) { $0+$1[i]*$1[j] } };a[i][8] = zip(rows,targets).reduce(0) { $0+$1.0[i]*$1.1 } }
 for i in 0..<8 {
 let pivot = (i..<8).max { abs(a[$0][i]) < abs(a[$1][i]) }!
 guard abs(a[pivot][i]) > 1e-9 else { return nil }
 if pivot != i { a.swapAt(pivot,i) }
 let divisor = a[i][i];for k in i...8 { a[i][k] /= divisor }
 for j in 0..<8 where j != i { let m = a[j][i];for k in i...8 { a[j][k] -= m*a[i][k] } }
 }
 let h = a.map { $0[8] }
 let c1 = SIMD3<Float>(Float(h[0]),Float(h[3]),Float(h[6]))
 let c2 = SIMD3<Float>(Float(h[1]),Float(h[4]),Float(h[7]))
 guard simd_length(c1) > 0.001,simd_length(c2) > 0.001 else { return nil }
 let x = simd_normalize(c1)
 let residual = c2-x*simd_dot(x,c2)
 guard simd_length(residual) > 0.001 else { return nil }
 let y = simd_normalize(residual),z = simd_cross(x,y)
 // Convert camera-forward coordinates to SceneKit's camera-facing coordinate system.
 let matrix = simd_float3x3(columns:(SIMD3(x.x,x.y,-x.z),SIMD3(y.x,y.y,-y.z),SIMD3(-z.x,-z.y,z.z)))
 let result = simd_normalize(simd_quatf(matrix))
 guard result.vector.x.isFinite,result.vector.y.isFinite,result.vector.z.isFinite,result.vector.w.isFinite else { return nil }
 return result
 }
}
