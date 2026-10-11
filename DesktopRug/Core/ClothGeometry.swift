import Foundation
import simd

public enum ClothGeometry {
    public static let liftProjection = SIMD2<Float>(0.16, 0.52)
    public static func project(_ point: SIMD3<Float>) -> SIMD2<Float> {
        SIMD2(point.x, point.y) + liftProjection * point.z
    }
    public static func pointInTriangle(_ point: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Bool {
        let v0 = b - a, v1 = c - a, v2 = point - a
        let cross = v0.x * v1.y - v0.y * v1.x
        guard abs(cross) > 0.0001 else { return false }
        let u = (v2.x * v1.y - v2.y * v1.x) / cross
        let v = (v0.x * v2.y - v0.y * v2.x) / cross
        return u >= 0 && v >= 0 && u + v <= 1
    }
    public static func hitVertex(at point: SIMD2<Float>, positions: [SIMD3<Float>], indices: [UInt32]) -> Int? {
        var best: Int?
        var bestHeight: Float = -.infinity
        for t in stride(from: 0, to: indices.count, by: 3) {
            let a = Int(indices[t]), b = Int(indices[t + 1]), c = Int(indices[t + 2])
            let pa = project(positions[a]), pb = project(positions[b]), pc = project(positions[c])
            guard pointInTriangle(point, pa, pb, pc) else { continue }
            let height = max(positions[a].z, positions[b].z, positions[c].z)
            if height > bestHeight {
                bestHeight = height
                best = [a, b, c].min { simd_distance_squared(project(positions[$0]), point) < simd_distance_squared(project(positions[$1]), point) }
            }
        }
        return best
    }
    public static func finderPoint(x: Float, y: Float, mainDisplayHeight: Float) -> SIMD2<Float> {
        SIMD2(x, mainDisplayHeight - y)
    }
}
