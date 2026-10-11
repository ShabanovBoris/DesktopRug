import Foundation
import simd

@main struct PhysicsBenchmark {
    static func main() {
        let sim = ClothSimulation(columns: 41, rows: 29, size: SIMD2(640,430), origin: .zero)
        sim.setCollisions([CollisionMound(center: SIMD2(320,215), halfExtent: SIMD2(65,60), height: 35)])
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<600 { sim.step() }
        let milliseconds = (CFAbsoluteTimeGetCurrent() - start) * 1000 / 300
        print("balanced physics milliseconds per 60 Hz frame:", milliseconds)
        let test = ClothSimulation(columns: 25,rows:19,size:SIMD2(480,320),origin:.zero)
        let vertical = ClothSimulation(columns: 25,rows:19,size:SIMD2(480,320),origin:.zero)
        vertical.grab(index:vertical.cornerIndices.last!);vertical.moveGrab(to:SIMD3(480,320,130))
        for _ in 0..<180 { vertical.step() }
        vertical.releaseGrab()
        for _ in 0..<1800 { vertical.step() }
        print("vertical release",vertical.positions.map(\.z).max()!,"settled",vertical.isSettled,"movement",vertical.maximumStepDisplacement)
        let index = test.cornerIndices.last!
        test.grab(index:index);test.moveGrab(to:SIMD3(280,200,130))
        for _ in 0..<180 { test.step() }
        print("held",test.positions.map(\.z).max()!,test.positions[index])
        test.releaseGrab()
        for i in 0..<1800 {
            test.step()
            if i % 300 == 299 { print("released",i+1,"maxHeight",test.positions.map(\.z).max()!,"corner",test.positions[index],"settled",test.isSettled,"stepMovement",test.maximumStepDisplacement,"stretch",test.maximumStretchRatio()) }
        }
    }
}
