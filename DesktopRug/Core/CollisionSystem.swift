import Foundation
import simd

public struct CollisionMound: Equatable, Sendable {
    public var center: SIMD2<Float>
    public var halfExtent: SIMD2<Float>
    public var height: Float

    public init(center: SIMD2<Float>, halfExtent: SIMD2<Float>, height: Float) {
        self.center = center
        self.halfExtent = simd_max(halfExtent, SIMD2(repeating: 1))
        self.height = max(0, height)
    }
}

public struct CollisionSurface: Sendable {
    public var mounds: [CollisionMound] = []
    public let floorHeight: Float = 1.6

    public init(mounds: [CollisionMound] = []) { self.mounds = mounds }

    public func sample(at point: SIMD2<Float>) -> (height: Float, gradient: SIMD2<Float>) {
        var height = floorHeight
        var gradient = SIMD2<Float>.zero
        for mound in mounds {
            let offset = (point - mound.center) / mound.halfExtent
            let r2 = simd_length_squared(offset)
            guard r2 < 1 else { continue }
            let falloff = 1 - r2
            // Additive compact kernels give overlapping icons a taller pile with a smooth boundary.
            height += mound.height * falloff * falloff
            gradient += -4 * mound.height * falloff * offset / mound.halfExtent
        }
        // Keep very large icon piles inside the desktop's usable lifting range, with a C1-continuous cap.
        if height > 129.6 {
            let attenuation = exp(-(height - 129.6) / 128)
            height = 129.6 + 128 * (1 - attenuation)
            gradient *= attenuation
        }
        return (height, gradient)
    }

    public func project(_ point: inout SIMD3<Float>) -> Bool {
        let surface = sample(at: SIMD2(point.x, point.y))
        let penetration = surface.height - point.z
        guard penetration > 0 else { return false }
        let normal = SIMD3(-surface.gradient.x, -surface.gradient.y, 1)
        point += normal * (penetration / simd_length_squared(normal))
        return true
    }
}
