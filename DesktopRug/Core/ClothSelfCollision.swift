import simd

struct ClothSelfCollision {
    let thickness: Float = 4
    private let columns: Int
    private let triangles: [SIMD3<Int>]
    private let edges: [SIMD2<Int>]
    private let gridPositions: [SIMD2<Int32>]
    private let cellSize: Float
    private let inverseCellSize: Float
    private let inverseEdgeCellSize: Float
    private var heads = [Int](repeating: -1, count: 16384)
    private var next: [Int] = []
    private var primitiveForNode: [Int] = []
    private var cells: [SIMD3<Int32>] = []
    private var queriedByVertex: [Int]
    private var queriedEdge: [Int]
    private var hasTurnedTriangle = false
    private(set) var contactCount = 0
    private(set) var edgeContactCount = 0

    init(columns: Int, indices: [UInt32], spacing: SIMD2<Float>) {
        self.columns = columns
        let faces = stride(from: 0, to: indices.count, by: 3).map {
            SIMD3(Int(indices[$0]), Int(indices[$0 + 1]), Int(indices[$0 + 2]))
        }
        triangles = faces
        var uniqueEdges: [SIMD2<Int>] = []
        var edgeIDs: [UInt64: Int] = [:]
        for face in faces {
            for side in 0..<3 {
                let a = face[side], b = face[(side + 1) % 3]
                let key = UInt64(min(a, b)) << 32 | UInt64(max(a, b))
                if edgeIDs[key] == nil {
                    edgeIDs[key] = uniqueEdges.count
                    uniqueEdges.append(SIMD2(a, b))
                }
            }
        }
        edges = uniqueEdges
        gridPositions = (0..<Int((indices.max() ?? 0) + 1)).map { SIMD2(Int32($0 / columns), Int32($0 % columns)) }
        queriedEdge = [Int](repeating: -1, count: uniqueEdges.count)
        cellSize = max(8, simd_length(spacing))
        inverseCellSize = 1 / cellSize
        inverseEdgeCellSize = 1 / max(6, cellSize * 0.5)
        queriedByVertex = [Int](repeating: -1, count: triangles.count)
        let capacity = triangles.count * 24
        next.reserveCapacity(capacity)
        primitiveForNode.reserveCapacity(capacity)
        cells.reserveCapacity(capacity)
    }

    private func hash(_ cell: SIMD3<Int32>) -> Int {
        let h = (cell.x &* 73856093) ^ (cell.y &* 19349663) ^ (cell.z &* 83492791)
        return Int(UInt32(bitPattern: h) & 16383)
    }

    private func cell(at point: SIMD3<Float>, inverseSize: Float) -> SIMD3<Int32> {
        SIMD3(Int32(floor(point.x * inverseSize)), Int32(floor(point.y * inverseSize)), Int32(floor(point.z * inverseSize)))
    }

    private mutating func buildHash(_ positions: [SIMD3<Float>], previous: [SIMD3<Float>]) {
        for i in heads.indices { heads[i] = -1 }
        for i in queriedByVertex.indices { queriedByVertex[i] = -1 }
        for i in queriedEdge.indices { queriedEdge[i] = -1 }
        hasTurnedTriangle = false
        next.removeAll(keepingCapacity: true)
        primitiveForNode.removeAll(keepingCapacity: true)
        cells.removeAll(keepingCapacity: true)
        for (index, triangle) in triangles.enumerated() {
            let a = positions[triangle.x], b = positions[triangle.y], c = positions[triangle.z]
            if simd_cross(b - a, c - a).z < 0 { hasTurnedTriangle = true }
            let oldA = previous[triangle.x], oldB = previous[triangle.y], oldC = previous[triangle.z]
            let lower = simd_min(simd_min(a, simd_min(b, c)), simd_min(oldA, simd_min(oldB, oldC))) - SIMD3(repeating: thickness)
            let upper = simd_max(simd_max(a, simd_max(b, c)), simd_max(oldA, simd_max(oldB, oldC))) + SIMD3(repeating: thickness)
            guard lower.x.isFinite && lower.y.isFinite && lower.z.isFinite && upper.x.isFinite && upper.y.isFinite && upper.z.isFinite else { continue }
            let lo = cell(at: lower, inverseSize: inverseCellSize), hi = cell(at: upper, inverseSize: inverseCellSize)
            for z in lo.z...hi.z { for y in lo.y...hi.y { for x in lo.x...hi.x {
                let key = SIMD3(x, y, z), bucket = hash(key)
                next.append(heads[bucket]); primitiveForNode.append(index); cells.append(key)
                heads[bucket] = next.count - 1
            } } }
        }
    }

    private func isNeighbour(_ vertex: Int, of triangle: SIMD3<Int>) -> Bool {
        areNeighbours(vertex, triangle.x) || areNeighbours(vertex, triangle.y) || areNeighbours(vertex, triangle.z)
    }

    static func closestPoint(_ p: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> (point: SIMD3<Float>, weights: SIMD3<Float>) {
        let ab = b - a, ac = c - a, ap = p - a
        let d1 = simd_dot(ab, ap), d2 = simd_dot(ac, ap)
        if d1 <= 0 && d2 <= 0 { return (a, SIMD3(1, 0, 0)) }
        let bp = p - b, d3 = simd_dot(ab, bp), d4 = simd_dot(ac, bp)
        if d3 >= 0 && d4 <= d3 { return (b, SIMD3(0, 1, 0)) }
        let vc = d1 * d4 - d3 * d2
        if vc <= 0 && d1 >= 0 && d3 <= 0 {
            let v = d1 / (d1 - d3)
            return (a + v * ab, SIMD3(1 - v, v, 0))
        }
        let cp = p - c, d5 = simd_dot(ab, cp), d6 = simd_dot(ac, cp)
        if d6 >= 0 && d5 <= d6 { return (c, SIMD3(0, 0, 1)) }
        let vb = d5 * d2 - d1 * d6
        if vb <= 0 && d2 >= 0 && d6 <= 0 {
            let w = d2 / (d2 - d6)
            return (a + w * ac, SIMD3(1 - w, 0, w))
        }
        let va = d3 * d6 - d5 * d4
        if va <= 0 && d4 - d3 >= 0 && d5 - d6 >= 0 {
            let w = (d4 - d3) / (d4 - d3 + d5 - d6)
            return (b + w * (c - b), SIMD3(0, 1 - w, w))
        }
        let inverse = 1 / (va + vb + vc), v = vb * inverse, w = vc * inverse
        return (a + ab * v + ac * w, SIMD3(1 - v - w, v, w))
    }

    mutating func resolve(_ positions: inout [SIMD3<Float>], previous: [SIMD3<Float>], pinned: Int?) {
        buildHash(positions, previous: previous)
        contactCount = 0
        edgeContactCount = 0
        for vertex in positions.indices {
            let movement = positions[vertex] - previous[vertex]
            let samples = max(1, Int(ceil(simd_length(movement) / (cellSize * 0.75))))
            for sample in 0...samples {
                let key = cell(at: previous[vertex] + movement * (Float(sample) / Float(samples)), inverseSize: inverseCellSize)
                var node = heads[hash(key)]
                while node >= 0 {
                    let triangleIndex = primitiveForNode[node]
                    if cells[node] == key && queriedByVertex[triangleIndex] != vertex {
                        queriedByVertex[triangleIndex] = vertex
                        let triangle = triangles[triangleIndex]
                        if !isNeighbour(vertex, of: triangle) {
                            resolve(vertex, triangle: triangle, positions: &positions, previous: previous, pinned: pinned)
                        }
                    }
                    node = next[node]
                }
            }
        }
        if hasTurnedTriangle || contactCount > 0 { resolveEdges(&positions, previous: previous, pinned: pinned) }
    }

    static func closestSegments(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>) -> (first: SIMD3<Float>, second: SIMD3<Float>, s: Float, t: Float) {
        let first = b - a, second = d - c, r = a - c
        let aa = simd_dot(first, first), ee = simd_dot(second, second), f = simd_dot(second, r)
        guard aa > 0.00001 && ee > 0.00001 else { return (a, c, 0, 0) }
        let bb = simd_dot(first, second), cc = simd_dot(first, r), denominator = aa * ee - bb * bb
        var s: Float = denominator > 0.00001 ? min(1, max(0, (bb * f - cc * ee) / denominator)) : 0
        var t = (bb * s + f) / ee
        if t < 0 { t = 0; s = min(1, max(0, -cc / aa)) }
        else if t > 1 { t = 1; s = min(1, max(0, (bb - cc) / aa)) }
        return (a + first * s, c + second * t, s, t)
    }

    private func areNeighbours(_ a: Int, _ b: Int) -> Bool {
        let delta = gridPositions[a] &- gridPositions[b]
        return abs(delta.x) <= 1 && abs(delta.y) <= 1
    }

    private mutating func buildEdgeHash(_ positions: [SIMD3<Float>], previous: [SIMD3<Float>]) {
        for i in heads.indices { heads[i] = -1 }
        next.removeAll(keepingCapacity: true)
        primitiveForNode.removeAll(keepingCapacity: true)
        cells.removeAll(keepingCapacity: true)
        for (index, edge) in edges.enumerated() {
            let a = positions[edge.x], b = positions[edge.y], oldA = previous[edge.x], oldB = previous[edge.y]
            let lower = simd_min(simd_min(a, b), simd_min(oldA, oldB)) - SIMD3(repeating: thickness * 0.5)
            let upper = simd_max(simd_max(a, b), simd_max(oldA, oldB)) + SIMD3(repeating: thickness * 0.5)
            let lo = cell(at: lower, inverseSize: inverseEdgeCellSize), hi = cell(at: upper, inverseSize: inverseEdgeCellSize)
            for z in lo.z...hi.z { for y in lo.y...hi.y { for x in lo.x...hi.x {
                let key = SIMD3(x, y, z), bucket = hash(key)
                next.append(heads[bucket]); primitiveForNode.append(index); cells.append(key)
                heads[bucket] = next.count - 1
            } } }
        }
    }

    private mutating func resolveEdges(_ positions: inout [SIMD3<Float>], previous: [SIMD3<Float>], pinned: Int?) {
        // Edge bounds use a smaller grid; triangle bounds generate many irrelevant edge pairs near a fold.
        buildEdgeHash(positions, previous: previous)
        for (edgeID, edge) in edges.enumerated() {
            let a = positions[edge.x], b = positions[edge.y], oldA = previous[edge.x], oldB = previous[edge.y]
            let lower = simd_min(simd_min(a, b), simd_min(oldA, oldB)) - SIMD3(repeating: thickness * 0.5)
            let upper = simd_max(simd_max(a, b), simd_max(oldA, oldB)) + SIMD3(repeating: thickness * 0.5)
            let lo = cell(at: lower, inverseSize: inverseEdgeCellSize), hi = cell(at: upper, inverseSize: inverseEdgeCellSize)
            for z in lo.z...hi.z { for y in lo.y...hi.y { for x in lo.x...hi.x {
                let key = SIMD3(x, y, z)
                var node = heads[hash(key)]
                while node >= 0 {
                    let otherID = primitiveForNode[node]
                    if cells[node] == key && otherID > edgeID && queriedEdge[otherID] != edgeID {
                        queriedEdge[otherID] = edgeID
                        let other = edges[otherID]
                        let otherLower = simd_min(simd_min(positions[other.x], positions[other.y]), simd_min(previous[other.x], previous[other.y])) - SIMD3(repeating: thickness * 0.5)
                        let otherUpper = simd_max(simd_max(positions[other.x], positions[other.y]), simd_max(previous[other.x], previous[other.y])) + SIMD3(repeating: thickness * 0.5)
                        let overlap = simd_min(upper, otherUpper) - simd_max(lower, otherLower)
                        if overlap.x >= 0 && overlap.y >= 0 && overlap.z >= 0
                            && !areNeighbours(edge.x, other.x) && !areNeighbours(edge.x, other.y) && !areNeighbours(edge.y, other.x) && !areNeighbours(edge.y, other.y) {
                            resolveEdge(edge, other, positions: &positions, previous: previous, pinned: pinned)
                        }
                    }
                    node = next[node]
                }
            } } }
        }
    }

    private mutating func resolveEdge(_ edge: SIMD2<Int>, _ other: SIMD2<Int>, positions: inout [SIMD3<Float>], previous: [SIMD3<Float>], pinned: Int?) {
        let a = positions[edge.x], b = positions[edge.y], c = positions[other.x], d = positions[other.y]
        let closest = Self.closestSegments(a, b, c, d)
        let delta = closest.first - closest.second, distanceSquared = simd_length_squared(delta)
        let crossedEdges = simd_cross(b - a, d - c)
        let oldA = previous[edge.x], oldB = previous[edge.y], oldC = previous[other.x], oldD = previous[other.y]
        let oldDelta = simd_mix(oldA, oldB, SIMD3(repeating: closest.s)) - simd_mix(oldC, oldD, SIMD3(repeating: closest.t))
        var normal: SIMD3<Float>
        if simd_length_squared(crossedEdges) > 0.0001 { normal = simd_normalize(crossedEdges) }
        else if distanceSquared > 0.0001 { normal = delta / sqrt(distanceSquared) }
        else if simd_length_squared(oldDelta) > 0.0001 { normal = simd_normalize(oldDelta) }
        else { normal = SIMD3(0, 0, 1) }
        let oldDistance = simd_dot(oldDelta, normal), currentDistance = simd_dot(delta, normal)
        var crossed = false
        if oldDistance * currentDistance < 0 && abs(oldDistance) > 0.001 {
            let t = oldDistance / (oldDistance - currentDistance)
            let atTime = Self.closestSegments(simd_mix(oldA, a, SIMD3(repeating: t)), simd_mix(oldB, b, SIMD3(repeating: t)), simd_mix(oldC, c, SIMD3(repeating: t)), simd_mix(oldD, d, SIMD3(repeating: t)))
            crossed = simd_distance_squared(atTime.first, atTime.second) < thickness * thickness * 0.0625
        }
        guard distanceSquared < thickness * thickness || crossed else { return }
        if !crossed && distanceSquared > 0.0001 { normal = delta / sqrt(distanceSquared) }
        else if oldDistance < 0 { normal = -normal }
        let penetration = thickness - simd_dot(delta, normal)
        guard penetration > 0 else { return }
        let wa: Float = edge.x == pinned ? 0 : 1, wb: Float = edge.y == pinned ? 0 : 1
        let wc: Float = other.x == pinned ? 0 : 1, wd: Float = other.y == pinned ? 0 : 1
        let s = closest.s, t = closest.t
        let mass = wa * (1 - s) * (1 - s) + wb * s * s + wc * (1 - t) * (1 - t) + wd * t * t
        guard mass > 0 else { return }
        let correction = normal * (penetration / mass)
        positions[edge.x] += wa * (1 - s) * correction; positions[edge.y] += wb * s * correction
        positions[other.x] -= wc * (1 - t) * correction; positions[other.y] -= wd * t * correction
        contactCount += 1; edgeContactCount += 1
    }

    private mutating func resolve(_ vertex: Int, triangle: SIMD3<Int>, positions: inout [SIMD3<Float>], previous: [SIMD3<Float>], pinned: Int?) {
        let a = positions[triangle.x], b = positions[triangle.y], c = positions[triangle.z]
        let cross = simd_cross(b - a, c - a)
        guard simd_length_squared(cross) > 0.0001 else { return }
        let normal = simd_normalize(cross)
        let closest = Self.closestPoint(positions[vertex], a, b, c)
        let delta = positions[vertex] - closest.point
        let distanceSquared = simd_length_squared(delta)
        let signedDistance = simd_dot(delta, normal)
        let oldA = previous[triangle.x], oldB = previous[triangle.y], oldC = previous[triangle.z]
        let oldCross = simd_cross(oldB - oldA, oldC - oldA)
        let oldNormal = simd_length_squared(oldCross) > 0.0001 ? simd_normalize(oldCross) : normal
        let oldDistance = simd_dot(previous[vertex] - oldA, oldNormal)
        let side: Float = abs(oldDistance) > 0.001 ? (oldDistance >= 0 ? 1 : -1) : (signedDistance >= 0 ? 1 : -1)
        var crossed = false
        if oldDistance * signedDistance < 0 && abs(oldDistance) > 0.001 {
            let t = oldDistance / (oldDistance - signedDistance)
            let hit = simd_mix(previous[vertex], positions[vertex], SIMD3(repeating: t))
            let hitA = simd_mix(oldA, a, SIMD3(repeating: t)), hitB = simd_mix(oldB, b, SIMD3(repeating: t)), hitC = simd_mix(oldC, c, SIMD3(repeating: t))
            let faceHit = Self.closestPoint(hit, hitA, hitB, hitC)
            crossed = simd_distance_squared(hit, faceHit.point) < thickness * thickness * 0.0625
        }
        guard distanceSquared < thickness * thickness || crossed else { return }
        // Preserve the previous side of the material instead of pushing an already crossed vertex farther through it.
        let insideFace = closest.weights.x > 0.0001 && closest.weights.y > 0.0001 && closest.weights.z > 0.0001
        let direction = insideFace || crossed || distanceSquared < 0.0001 ? normal * side : delta / sqrt(distanceSquared)
        let distance = simd_dot(delta, direction)
        let penetration = thickness - distance
        guard penetration > 0 else { return }
        let w: Float = vertex == pinned ? 0 : 1
        let wa: Float = triangle.x == pinned ? 0 : 1, wb: Float = triangle.y == pinned ? 0 : 1, wc: Float = triangle.z == pinned ? 0 : 1
        let bary = closest.weights
        let inverseMass = w + wa * bary.x * bary.x + wb * bary.y * bary.y + wc * bary.z * bary.z
        guard inverseMass > 0 else { return }
        let correction = direction * (penetration / inverseMass)
        positions[vertex] += w * correction
        positions[triangle.x] -= wa * bary.x * correction
        positions[triangle.y] -= wb * bary.y * correction
        positions[triangle.z] -= wc * bary.z * correction
        contactCount += 1
    }
}
