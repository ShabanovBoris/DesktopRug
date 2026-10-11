import XCTest
import simd
#if SWIFT_PACKAGE
@testable import DesktopRugCore
#endif

final class ClothSimulationTests: XCTestCase {
    private func cloth() -> ClothSimulation {
        ClothSimulation(columns: 25, rows: 19, size: SIMD2(480, 320), origin: .zero)
    }

    func testMeshTopologyAndUVs() {
        let sim = cloth()
        XCTAssertEqual(sim.positions.count, 475)
        XCTAssertEqual(sim.indices.count, 24 * 18 * 6)
        XCTAssertEqual(sim.uvs.first, .zero)
        XCTAssertEqual(sim.uvs.last, SIMD2(1, 1))
        XCTAssertTrue(sim.indices.allSatisfy { $0 < sim.positions.count })
    }

    func testOverlappingObjectsAddHeightAndSmoothBoundary() {
        let mound = CollisionMound(center: SIMD2(220, 160), halfExtent: SIMD2(65, 55), height: 34)
        let one = CollisionSurface(mounds: [mound])
        let pile = CollisionSurface(mounds: [mound, mound])
        XCTAssertEqual(one.sample(at: mound.center).height, 35.6, accuracy: 0.001)
        XCTAssertEqual(pile.sample(at: mound.center).height, 69.6, accuracy: 0.001)
        XCTAssertEqual(pile.sample(at: SIMD2(285, 160)).height, 1.6, accuracy: 0.001)
        XCTAssertLessThan(simd_length(pile.sample(at: SIMD2(284.99, 160)).gradient), 0.002)
    }

    func testOneObjectCreatesLocalizedBumpWithoutPenetration() {
        let sim = cloth()
        sim.setCollisions([CollisionMound(center: SIMD2(240, 160), halfExtent: SIMD2(70, 65), height: 45)])
        for _ in 0..<720 { sim.step() }
        let center = sim.positions[9 * 25 + 12]
        XCTAssertGreaterThan(center.z, 35)
        XCTAssertLessThan(sim.positions[0].z, 8)
        for p in sim.positions { XCTAssertGreaterThanOrEqual(p.z + 0.002, sim.collisions.sample(at: SIMD2(p.x, p.y)).height) }
        XCTAssertLessThan(sim.maximumStretchRatio(), 1.12)
        XCTAssertEqual(sim.recoveryCount, 0)
    }

    func testLargeOverlappingPileIsBoundedAndSimulationRemainsStable() {
        let mound = CollisionMound(center: SIMD2(240,160),halfExtent: SIMD2(70,65),height: 150)
        let pile = Array(repeating:mound,count:64)
        let surface = CollisionSurface(mounds:pile)
        XCTAssertLessThan(surface.sample(at:mound.center).height,258)
        let sim=cloth()
        sim.setCollisions(pile)
        for _ in 0..<900 { sim.step() }
        XCTAssertTrue(sim.positions.allSatisfy {$0.x.isFinite && $0.y.isFinite && $0.z.isFinite})
        XCTAssertEqual(sim.recoveryCount,0)
    }

    func testCornerLiftDeformsMeshAndSettlesAfterRelease() {
        let sim = cloth()
        let corner = sim.cornerIndices.last!
        sim.grab(index: corner)
        sim.moveGrab(to: SIMD3(280, 200, 130))
        for _ in 0..<180 { sim.step() }
        XCTAssertGreaterThan(sim.positions[corner].z, 120)
        XCTAssertGreaterThan(sim.positions[corner - 1].z, 80)
        XCTAssertGreaterThan(sim.positions.filter { $0.z > 10 }.count, 10)
        sim.releaseGrab()
        for _ in 0..<1800 { sim.step() }
        XCTAssertTrue(sim.isSettled)
        XCTAssertLessThan(sim.positions[corner].z, 6)
        // Inward dragging folds the sheet; settling must lower the held corner without forcing the whole rug flat.
        XCTAssertLessThan(sim.positions.map(\.z).max()!, 65)
        XCTAssertLessThan(sim.maximumStretchRatio(), 1.12)
        XCTAssertEqual(sim.recoveryCount, 0)
    }

    func testVerticalCornerReleaseLowersTheCornerAndStopsWork() {
        let sim = cloth()
        let corner = sim.cornerIndices.last!
        sim.grab(index: corner)
        sim.moveGrab(to: SIMD3(480, 320, 130))
        for _ in 0..<180 { sim.step() }
        XCTAssertGreaterThan(sim.positions[corner].z, 120)
        sim.releaseGrab()
        for _ in 0..<1800 { sim.step() }
        XCTAssertLessThan(sim.positions[corner].z, 6)
        XCTAssertTrue(sim.isSettled)
        XCTAssertEqual(sim.advance(elapsed: 1), 0)
        XCTAssertLessThan(sim.maximumStretchRatio(), 1.12)
        XCTAssertEqual(sim.recoveryCount, 0)
    }

    func testExtremeInteractionRemainsFiniteAndBounded() {
        let sim = cloth()
        sim.grab(index: 0)
        for i in 0..<240 {
            sim.moveGrab(to: SIMD3(i % 2 == 0 ? 1e7 : -1e7, Float(i % 3) * 5000, 1e6))
            sim.step()
        }
        sim.moveGrab(to: SIMD3(.nan, 0, 0))
        sim.releaseGrab()
        for _ in 0..<900 { sim.step() }
        XCTAssertTrue(sim.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        XCTAssertLessThan(sim.positions.map(\.z).max()!, 400)
        XCTAssertEqual(sim.recoveryCount, 0)
    }

    func testFixedTimestepAndIdleSleep() {
        let a = cloth(), b = cloth()
        a.grab(index: 0); b.grab(index: 0)
        a.moveGrab(to: SIMD3(80, 50, 90)); b.moveGrab(to: SIMD3(80, 50, 90))
        for _ in 0..<60 { _ = a.advance(elapsed: 1 / 60) }
        for _ in 0..<120 { _ = b.advance(elapsed: 1 / 120) }
        for (pa, pb) in zip(a.positions, b.positions) { XCTAssertLessThan(simd_distance(pa, pb), 0.001) }
        let still = cloth()
        for _ in 0..<200 { still.step() }
        XCTAssertTrue(still.isSettled)
        XCTAssertEqual(still.advance(elapsed: 5), 0)
        still.translate(by: SIMD2(40, -20))
        XCTAssertFalse(still.isSettled)
        XCTAssertEqual(still.origin, SIMD2(40, -20))
    }

    func testGeometryHitTestingAndFinderCoordinateConversion() {
        let sim = cloth()
        XCTAssertNotNil(ClothGeometry.hitVertex(at: SIMD2(200, 100), positions: sim.positions, indices: sim.indices))
        XCTAssertNil(ClothGeometry.hitVertex(at: SIMD2(-5, 100), positions: sim.positions, indices: sim.indices))
        XCTAssertEqual(ClothGeometry.finderPoint(x: 200, y: 90, mainDisplayHeight: 1117), SIMD2(200, 1027))
    }

    func testRotationPreservesFoldHeightsMaterialAndGrabbedCorner() {
        let sim = cloth(), corner = sim.cornerIndices.last!
        sim.grab(index: corner)
        sim.moveGrab(to: SIMD3(420, 290, 110))
        for _ in 0..<120 { sim.step() }
        let before = sim.positions, uvs = sim.uvs, origin = sim.origin, stretch = sim.maximumStretchRatio()
        sim.setRotation(degrees: 90)
        XCTAssertEqual(sim.origin, origin)
        XCTAssertEqual(sim.uvs, uvs)
        XCTAssertEqual(sim.grabbedIndex, corner)
        XCTAssertEqual(sim.maximumStretchRatio(), stretch, accuracy: 0.0001)
        for (old, rotated) in zip(before, sim.positions) {
            XCTAssertEqual(rotated.x, sim.center.x - (old.y - sim.center.y), accuracy: 0.001)
            XCTAssertEqual(rotated.y, sim.center.y + (old.x - sim.center.x), accuracy: 0.001)
            XCTAssertEqual(rotated.z, old.z)
        }
        for _ in 0..<30 { sim.step() }
        XCTAssertEqual(sim.positions[corner].x, 110, accuracy: 0.01)
        XCTAssertEqual(sim.positions[corner].y, 340, accuracy: 0.01)
        XCTAssertGreaterThan(sim.positions[corner].z, 100)
        XCTAssertEqual(sim.recoveryCount, 0)
    }

    func testRotatingSettledClothDoesNotInjectVelocity() {
        let sim = cloth()
        for _ in 0..<200 { sim.step() }
        XCTAssertTrue(sim.isSettled)
        sim.setRotation(degrees: 405)
        XCTAssertEqual(sim.rotationDegrees, 45)
        XCTAssertFalse(sim.isSettled)
        sim.step()
        XCTAssertLessThan(sim.maximumStepDisplacement, 0.01)
        let positions = sim.positions
        sim.setRotation(degrees: .nan)
        XCTAssertEqual(sim.rotationDegrees, 45)
        XCTAssertEqual(sim.positions, positions)
        XCTAssertEqual(sim.recoveryCount, 0)
    }

    func testResetAndRebuildKeepRotatedOrientationAndHitTesting() {
        let sim = ClothSimulation(columns: 25, rows: 19, size: SIMD2(480, 320), origin: .zero, rotationDegrees: 270)
        XCTAssertEqual(sim.rotationDegrees, -90)
        sim.grab(index: 0)
        sim.moveGrab(to: SIMD3(110, 340, 100))
        for _ in 0..<120 { sim.step() }
        sim.reset()
        XCTAssertEqual(sim.rotationDegrees, -90)
        XCTAssertEqual(sim.positions[0].x, 80, accuracy: 0.001)
        XCTAssertEqual(sim.positions[0].y, 400, accuracy: 0.001)
        XCTAssertEqual(sim.planarBounds.lower.x, 80, accuracy: 0.001)
        XCTAssertEqual(sim.planarBounds.upper.y, 400, accuracy: 0.001)
        XCTAssertNotNil(ClothGeometry.hitVertex(at: SIMD2(240, 370), positions: sim.positions, indices: sim.indices))
        XCTAssertNil(ClothGeometry.hitVertex(at: SIMD2(20, 160), positions: sim.positions, indices: sim.indices))
        let rebuilt = ClothSimulation(columns: 29, rows: 21, size: sim.size, origin: sim.origin, rotationDegrees: sim.rotationDegrees)
        XCTAssertEqual(rebuilt.positions[0].x, sim.positions[0].x, accuracy: 0.001)
        XCTAssertEqual(rebuilt.positions[0].y, sim.positions[0].y, accuracy: 0.001)
        let extent = ClothGeometry.rotatedHalfExtent(size: sim.size, degrees: 90)
        XCTAssertEqual(extent.x, 160, accuracy: 0.001)
        XCTAssertEqual(extent.y, 240, accuracy: 0.001)
    }

    func testRotatedClothCollidesWithStationaryDesktopObjects() {
        let sim = ClothSimulation(columns: 41, rows: 15, size: SIMD2(900, 250), origin: SIMD2(200, 300), rotationDegrees: 90)
        let mound = CollisionMound(center: SIMD2(650, 800), halfExtent: SIMD2(65, 60), height: 40)
        sim.setCollisions([mound])
        for _ in 0..<720 { sim.step() }
        XCTAssertEqual(sim.collisions.mounds, [mound])
        let nearest = sim.positions.min { simd_distance(SIMD2($0.x, $0.y), mound.center) < simd_distance(SIMD2($1.x, $1.y), mound.center) }!
        XCTAssertGreaterThan(nearest.z, 30)
        for p in sim.positions { XCTAssertGreaterThanOrEqual(p.z + 0.002, sim.collisions.sample(at: SIMD2(p.x, p.y)).height) }
        XCTAssertLessThan(sim.maximumStretchRatio(), 1.12)
        XCTAssertEqual(sim.recoveryCount, 0)
    }

    func testLegacyConfigurationLoadsWithZeroRotation() throws {
        var original = RugConfiguration()
        original.originX = 430; original.originY = 125; original.texture = .sovietFloral
        original.finderEnabled = true; original.damping = 0.35
        original.manualMounds = [ManualMound(x: 200, y: 300)]
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        legacy.removeValue(forKey: "rotationDegrees")
        let restored = try JSONDecoder().decode(RugConfiguration.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.rotationDegrees, 0)
    }

    func testConfigurationRoundTripAndInvalidValues() throws {
        var config = RugConfiguration()
        config.originX = -90; config.originY = 1500; config.texture = .indigo; config.rotationDegrees = -47.5
        config.manualMounds = [ManualMound(x: 400, y: 500)]
        let restored = try JSONDecoder().decode(RugConfiguration.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(config, restored)
        config.width = .nan; config.height = -1; config.damping = .infinity; config.frameRate = 999; config.rotationDegrees = .nan
        config.sanitize()
        XCTAssertEqual(config.width, 640); XCTAssertEqual(config.height, 200)
        XCTAssertEqual(config.damping, 0.12); XCTAssertEqual(config.frameRate, 60)
        XCTAssertEqual(config.rotationDegrees, 0)
    }

    func testVertexContactsTriangleInteriorEvenWhenVerticesAreFarApart() {
        var points = (0..<16).map { SIMD3<Float>(200 + Float($0) * 20, 200, 0) }
        points[0] = SIMD3(20, 20, 1)
        points[12] = SIMD3(0, 0, 0); points[13] = SIMD3(80, 0, 0); points[15] = SIMD3(0, 80, 0)
        let before = points
        var contacts = ClothSelfCollision(columns: 4, indices: [12, 13, 15], spacing: SIMD2(20, 20))
        for _ in 0..<3 { contacts.resolve(&points, previous: before, pinned: nil) }
        let closest = ClothSelfCollision.closestPoint(points[0], points[12], points[13], points[15])
        XCTAssertGreaterThanOrEqual(simd_distance(points[0], closest.point), contacts.thickness - 0.01)
        XCTAssertGreaterThan(points[0].z, 1)
    }

    func testFastVertexCrossingIsReturnedToItsPreviousSide() {
        var before = (0..<16).map { SIMD3<Float>(200 + Float($0) * 20, 200, 0) }
        before[0] = SIMD3(20, 20, 20)
        before[12] = SIMD3(0, 0, 0); before[13] = SIMD3(80, 0, 0); before[15] = SIMD3(0, 80, 0)
        var points = before
        points[0].z = -20
        var contacts = ClothSelfCollision(columns: 4, indices: [12, 13, 15], spacing: SIMD2(20, 20))
        contacts.resolve(&points, previous: before, pinned: nil)
        XCTAssertGreaterThan(contacts.contactCount, 0)
        let n = simd_normalize(simd_cross(points[13] - points[12], points[15] - points[12]))
        XCTAssertGreaterThan(simd_dot(points[0] - points[12], n), 0)
    }

    func testDeepFoldDoesNotCrossNonNeighbourTriangles() {
        let sim = ClothSimulation(columns: 41, rows: 29, size: SIMD2(640, 430), origin: .zero)
        sim.setCollisions([CollisionMound(center: SIMD2(320, 215), halfExtent: SIMD2(55, 48), height: 35)])
        let corner = sim.cornerIndices.last!, start = sim.positions[corner]
        sim.grab(index: corner)
        sim.moveGrab(to: start + SIMD3(-499.2, -301, 200))
        for _ in 0..<300 { sim.step() }
        XCTAssertEqual(intersections(in: sim), 0)
        sim.releaseGrab()
        for _ in 0..<2400 { sim.step() }
        XCTAssertEqual(intersections(in: sim), 0)
        XCTAssertTrue(sim.isSettled)
        XCTAssertEqual(sim.recoveryCount, 0)
    }

    func testCrossingEdgesAreSeparatedWithoutAnyVertexFaceContact() {
        var points = (0..<16).map { SIMD3<Float>(2000 + Float($0) * 100, 2000, 0) }
        points[0] = SIMD3(-100, 0, 0); points[1] = SIMD3(100, 0, 0); points[4] = SIMD3(-100, -5, 0)
        points[12] = SIMD3(0, -100, 0.4); points[13] = SIMD3(0, 100, 0.4); points[15] = SIMD3(5, -100, 0.4)
        let before = points
        var contacts = ClothSelfCollision(columns: 4, indices: [0, 1, 4, 12, 13, 15], spacing: SIMD2(20, 20))
        var edgeContacts = 0
        for _ in 0..<10 { contacts.resolve(&points, previous: before, pinned: nil); edgeContacts += contacts.edgeContactCount }
        let nearest = ClothSelfCollision.closestSegments(points[0], points[1], points[12], points[13])
        XCTAssertGreaterThan(edgeContacts, 0)
        XCTAssertGreaterThanOrEqual(simd_distance(nearest.first, nearest.second), contacts.thickness - 0.01)
    }

    private func segmentCrossesTriangle(_ from: SIMD3<Float>, _ to: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> Bool {
        let direction = to - from, ab = b - a, ac = c - a
        let h = simd_cross(direction, ac), determinant = simd_dot(ab, h)
        guard abs(determinant) > 0.0001 else { return false }
        let inverse = 1 / determinant, s = from - a
        let u = inverse * simd_dot(s, h)
        guard u > 0.0001 && u < 0.9999 else { return false }
        let q = simd_cross(s, ab), v = inverse * simd_dot(direction, q)
        guard v > 0.0001 && u + v < 0.9999 else { return false }
        let t = inverse * simd_dot(ac, q)
        return t > 0.0001 && t < 0.9999
    }

    private func intersections(in sim: ClothSimulation) -> Int {
        var triangles: [SIMD3<Int>] = []
        var lower: [SIMD3<Float>] = [], upper: [SIMD3<Float>] = []
        for offset in stride(from: 0, to: sim.indices.count, by: 3) {
            let a = Int(sim.indices[offset]), b = Int(sim.indices[offset + 1]), c = Int(sim.indices[offset + 2])
            triangles.append(SIMD3(a, b, c))
            let pa = sim.positions[a], pb = sim.positions[b], pc = sim.positions[c]
            lower.append(simd_min(pa, simd_min(pb, pc)))
            upper.append(simd_max(pa, simd_max(pb, pc)))
        }
        var count = 0
        for i in triangles.indices {
            for j in (i + 1)..<triangles.count {
                let overlap = simd_min(upper[i], upper[j]) - simd_max(lower[i], lower[j])
                if overlap.x < 0 || overlap.y < 0 || overlap.z < 0 { continue }
                let first = triangles[i], second = triangles[j]
                var neighbours = false
                for a in 0..<3 { for b in 0..<3 {
                    if abs(first[a] / sim.columns - second[b] / sim.columns) <= 1 && abs(first[a] % sim.columns - second[b] % sim.columns) <= 1 { neighbours = true }
                } }
                if neighbours { continue }
                let pa = sim.positions[first.x], pb = sim.positions[first.y], pc = sim.positions[first.z]
                let qa = sim.positions[second.x], qb = sim.positions[second.y], qc = sim.positions[second.z]
                if segmentCrossesTriangle(pa, pb, qa, qb, qc) || segmentCrossesTriangle(pb, pc, qa, qb, qc) || segmentCrossesTriangle(pc, pa, qa, qb, qc)
                    || segmentCrossesTriangle(qa, qb, pa, pb, pc) || segmentCrossesTriangle(qb, qc, pa, pb, pc) || segmentCrossesTriangle(qc, qa, pa, pb, pc) { count += 1 }
            }
        }
        return count
    }
}
