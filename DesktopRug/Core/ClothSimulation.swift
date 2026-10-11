import Foundation
import simd

public struct ClothParameters: Sendable {
    public var stiffness: Float = 0.88
    public var bending: Float = 0.36
    public var damping: Float = 0.12
    public var gravity: Float = 980
    public var iterations: Int = 8
    public init() {}
}

private struct DistanceConstraint {
    var a: Int
    var b: Int
    var length: Float
    var isBending: Bool
    var lambda: Float = 0
}

public final class ClothSimulation {
    public static let timestep: Float = 1 / 120
    public let columns: Int
    public let rows: Int
    public let size: SIMD2<Float>
    public private(set) var origin: SIMD2<Float>
    public private(set) var positions: [SIMD3<Float>]
    public let uvs: [SIMD2<Float>]
    public let indices: [UInt32]
    public private(set) var isSettled = false
    public private(set) var recoveryCount = 0
    public private(set) var maximumStepDisplacement: Float = 0
    public private(set) var selfContactCount = 0
    public private(set) var edgeSelfContactCount = 0
    public var parameters = ClothParameters()
    public private(set) var collisions = CollisionSurface()
    public private(set) var grabbedIndex: Int?
    private var previous: [SIMD3<Float>]
    private var beforeStep: [SIMD3<Float>]
    private var constraints: [DistanceConstraint] = []
    private var pinTarget = SIMD3<Float>.zero
    private var pinPosition = SIMD3<Float>.zero
    private var quietSteps = 0
    private var accumulator: Float = 0
    private var selfCollision: ClothSelfCollision

    public init(columns: Int, rows: Int, size: SIMD2<Float>, origin: SIMD2<Float>) {
        precondition(columns >= 3 && rows >= 3 && columns * rows < 65536)
        precondition(size.x > 0 && size.y > 0 && size.x.isFinite && size.y.isFinite)
        self.columns = columns; self.rows = rows; self.size = size; self.origin = origin
        var points: [SIMD3<Float>] = []
        var coordinates: [SIMD2<Float>] = []
        var triangles: [UInt32] = []
        for y in 0..<rows {
            for x in 0..<columns {
                let uv = SIMD2(Float(x) / Float(columns - 1), Float(y) / Float(rows - 1))
                let p = origin + uv * size
                points.append(SIMD3(p.x, p.y, 1.6))
                coordinates.append(uv)
                if x < columns - 1 && y < rows - 1 {
                    let a = UInt32(y * columns + x), b = a + 1, c = a + UInt32(columns), d = c + 1
                    triangles.append(contentsOf: [a, b, c, b, d, c])
                }
            }
        }
        positions = points; previous = points; beforeStep = points; uvs = coordinates; indices = triangles
        selfCollision = ClothSelfCollision(columns: columns, indices: triangles, spacing: size / SIMD2(Float(columns - 1), Float(rows - 1)))
        for y in 0..<rows {
            for x in 0..<columns {
                let a = y * columns + x
                if x + 1 < columns { addConstraint(a, a + 1, bending: false) }
                if y + 1 < rows { addConstraint(a, a + columns, bending: false) }
                if x + 1 < columns && y + 1 < rows {
                    addConstraint(a, a + columns + 1, bending: false)
                    addConstraint(a + 1, a + columns, bending: false)
                }
                if x + 2 < columns { addConstraint(a, a + 2, bending: true) }
                if y + 2 < rows { addConstraint(a, a + columns * 2, bending: true) }
            }
        }
    }

    public var cornerIndices: [Int] { [0, columns - 1, (rows - 1) * columns, rows * columns - 1] }

    private func addConstraint(_ a: Int, _ b: Int, bending: Bool) {
        constraints.append(DistanceConstraint(a: a, b: b, length: simd_distance(positions[a], positions[b]), isBending: bending))
    }

    public func wake() { quietSteps = 0; isSettled = false; accumulator = 0 }

    public func setCollisions(_ mounds: [CollisionMound]) {
        guard mounds != collisions.mounds else { return }
        collisions.mounds = mounds
        wake()
    }

    public func translate(by delta: SIMD2<Float>) {
        guard delta.x.isFinite && delta.y.isFinite else { return }
        let d = SIMD3(delta.x, delta.y, 0)
        origin += delta
        for i in positions.indices { positions[i] += d; previous[i] += d }
        pinTarget += d; pinPosition += d
        wake()
    }

    public func grab(index: Int) {
        guard positions.indices.contains(index) else { return }
        grabbedIndex = index; pinTarget = positions[index]; pinPosition = pinTarget
        wake()
    }

    public func moveGrab(to target: SIMD3<Float>) {
        guard grabbedIndex != nil && target.x.isFinite && target.y.isFinite && target.z.isFinite else { return }
        let center = origin + size / 2
        let reach = simd_length(size) * 1.2
        pinTarget = SIMD3(min(max(target.x, center.x - reach), center.x + reach), min(max(target.y, center.y - reach), center.y + reach), min(max(target.z, 2), 350))
        quietSteps = 0; isSettled = false
    }

    public func releaseGrab() {
        if let i = grabbedIndex { previous[i] = positions[i] }
        grabbedIndex = nil
        wake()
    }

    public func advance(elapsed: Float) -> Int {
        guard !isSettled && elapsed.isFinite && elapsed > 0 else { return 0 }
        // Bound catch-up after sleep or a blocked run loop; fixed dt keeps the constraint stiffness stable.
        accumulator = min(accumulator + elapsed, 8 * Self.timestep)
        var steps = 0
        while accumulator >= Self.timestep && !isSettled {
            step()
            accumulator -= Self.timestep
            steps += 1
        }
        return steps
    }

    public func step() {
        guard !isSettled else { return }
        let dt = Self.timestep
        let drag = pow(max(0, 1 - parameters.damping), dt * 60)
        let acceleration = SIMD3<Float>(0, 0, -parameters.gravity * dt * dt)
        for i in positions.indices {
            beforeStep[i] = positions[i]
            var velocity = (positions[i] - previous[i]) * drag
            let length = simd_length(velocity)
            if length > 18 { velocity *= 18 / length }
            previous[i] = positions[i]
            positions[i] += velocity + acceleration
        }
        if let pin = grabbedIndex {
            let delta = pinTarget - pinPosition
            let length = simd_length(delta)
            pinPosition += delta * min(1, 32 / max(length, 0.001))
            positions[pin] = pinPosition
        }
        for c in constraints.indices { constraints[c].lambda = 0 }
        let stretchCompliance = (1 - min(max(parameters.stiffness, 0.4), 1)) * 0.000008
        let bendCompliance = (1 - min(max(parameters.bending, 0.05), 1)) * 0.06 + 0.0006
        let iterations = max(4, parameters.iterations) + (grabbedIndex == nil ? 0 : 4)
        selfContactCount = 0
        edgeSelfContactCount = 0
        for iteration in 0..<iterations {
            for offset in constraints.indices {
                let i = iteration % 2 == 0 ? offset : constraints.count - 1 - offset
                let a = constraints[i].a, b = constraints[i].b
                let delta = positions[a] - positions[b]
                let length = simd_length(delta)
                guard length > 0.00001 else { continue }
                let wa: Float = a == grabbedIndex ? 0 : 1
                let wb: Float = b == grabbedIndex ? 0 : 1
                let alpha = (constraints[i].isBending ? bendCompliance : stretchCompliance) / (dt * dt)
                let lambda = (-(length - constraints[i].length) - alpha * constraints[i].lambda) / (wa + wb + alpha)
                constraints[i].lambda += lambda
                let correction = delta * (lambda / length)
                positions[a] += wa * correction
                positions[b] -= wb * correction
            }
            for i in positions.indices where i != grabbedIndex { _ = collisions.project(&positions[i]) }
            if let pin = grabbedIndex { positions[pin] = pinPosition }
            if iteration == iterations / 2 || iteration == iterations - 1 {
                selfCollision.resolve(&positions, previous: beforeStep, pinned: grabbedIndex)
                selfContactCount += selfCollision.contactCount
                edgeSelfContactCount += selfCollision.edgeContactCount
            }
        }
        var maximum: Float = 0
        for i in positions.indices {
            let surface = collisions.sample(at: SIMD2(positions[i].x, positions[i].y))
            if i != grabbedIndex && positions[i].z < surface.height + 0.15 {
                positions[i].z = max(positions[i].z, surface.height)
                let n = simd_normalize(SIMD3(-surface.gradient.x, -surface.gradient.y, 1))
                var v = positions[i] - previous[i]
                v -= n * min(0, simd_dot(v, n))
                let tangent = v - n * simd_dot(v, n)
                let speed = simd_length(tangent)
                if speed > 0.000001 {
                    let friction = tangent * min(1, parameters.gravity * dt * dt * 0.85 / speed)
                    positions[i] -= friction
                    v -= friction
                    positions[i].z = max(positions[i].z, collisions.sample(at: SIMD2(positions[i].x, positions[i].y)).height)
                }
                previous[i] = positions[i] - v
            }
            let p = positions[i]
            if !p.x.isFinite || !p.y.isFinite || !p.z.isFinite || simd_length(SIMD2(p.x, p.y) - origin) > simd_length(size) * 8 || abs(p.z) > 2000 {
                reset(); recoveryCount += 1; return
            }
            maximum = max(maximum, simd_distance(p, beforeStep[i]))
        }
        maximumStepDisplacement = maximum
        if maximum < 0.025 && grabbedIndex == nil { quietSteps += 1 } else { quietSteps = 0 }
        if quietSteps >= 90 {
            isSettled = true
            for i in positions.indices { previous[i] = positions[i] }
        }
    }

    public func reset() {
        for i in positions.indices {
            let xy = origin + uvs[i] * size
            let p = SIMD3(xy.x, xy.y, collisions.sample(at: xy).height + 1)
            positions[i] = p; previous[i] = p
        }
        grabbedIndex = nil
        wake()
    }

    public func maximumStretchRatio() -> Float {
        var result: Float = 1
        for c in constraints where !c.isBending { result = max(result, simd_distance(positions[c.a], positions[c.b]) / c.length) }
        return result
    }
}
