import AppKit
import MetalKit
import simd

private struct RugGPUVertex {
    var position: SIMD3<Float> = .zero
    var normal: SIMD3<Float> = SIMD3(0,0,1)
    var uv: SIMD2<Float> = .zero
    var material: Float = 0
}
private struct RugUniforms {
    var viewport: SIMD2<Float>
    var origin: SIMD2<Float>
    var shadowOffset: SIMD2<Float> = .zero
    var options: SIMD2<Float>
}
private struct FringeSegment { var a: Int; var b: Int; var innerA: Int; var innerB: Int; var t: Float }
private struct DebugGPUVolume { var centerExtent: SIMD4<Float>; var height: SIMD4<Float> }

enum RugRendererError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { if case .unavailable(let message) = self { return message }; return nil }
}

@MainActor final class RugRenderer: NSObject, MTKViewDelegate {
    private(set) var simulation: ClothSimulation
    var screenOrigin = SIMD2<Float>.zero
    var configuration: RugConfiguration
    var onSettled: (() -> Void)?
    var onFrame: (() -> Void)?
    private(set) var frameCount = 0
    private(set) var droppedFrames = 0
    private(set) var physicsMilliseconds: Double = 0
    private(set) var gpuMilliseconds: Double = 0
    private(set) var frameMilliseconds: Double = 0
    private(set) var actualFPS: Double = 0
    private var lastTime: CFTimeInterval = 0
    private var fpsStart: CFTimeInterval = 0
    private var fpsFrames = 0
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let rugPipeline: MTLRenderPipelineState
    private let shadowPipeline: MTLRenderPipelineState
    private let debugPipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let overlayDepthState: MTLDepthStencilState
    private var textures: [RugTexture: MTLTexture] = [:]
    private var vertexBuffers: [MTLBuffer] = []
    private var indexBuffer: MTLBuffer!
    private var vertices: [RugGPUVertex] = []
    private var normals: [SIMD3<Float>] = []
    private var meshIndices: [UInt32] = []
    private var boundary: [(Int,Int)] = []
    private var fringe: [FringeSegment] = []
    private var bufferIndex = 0
    private let inFlight = DispatchSemaphore(value: 3)
    private let blurOffsets: [SIMD2<Float>] = [.zero,SIMD2(-3,0),SIMD2(3,0),SIMD2(0,-3),SIMD2(0,3),SIMD2(-2,-2),SIMD2(2,-2),SIMD2(-2,2),SIMD2(2,2)]

    init(view: MTKView, simulation: ClothSimulation, configuration: RugConfiguration) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw RugRendererError.unavailable("Metal is unavailable on this Mac.") }
        self.device = device; self.queue = queue; self.simulation = simulation; self.configuration = configuration
        view.device = device
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColorMake(0,0,0,0)
        view.sampleCount = 1
        view.layer?.isOpaque = false
        view.framebufferOnly = true
        let library: MTLLibrary
        if let compiled = device.makeDefaultLibrary() { library = compiled }
        else {
            guard let url = Bundle.main.url(forResource: "RugShaders", withExtension: "metal") else { throw RugRendererError.unavailable("The Metal shader source is missing.") }
            library = try device.makeLibrary(source: String(contentsOf: url), options: nil)
        }
        func pipeline(_ vertex: String, _ fragment: String) throws -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: vertex)
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            descriptor.depthAttachmentPixelFormat = .depth32Float
            let color = descriptor.colorAttachments[0]!
            color.isBlendingEnabled = true
            color.sourceRGBBlendFactor = .one; color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.sourceAlphaBlendFactor = .one; color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        rugPipeline = try pipeline("rugVertex","rugFragment")
        shadowPipeline = try pipeline("shadowVertex","shadowFragment")
        debugPipeline = try pipeline("debugVertex","debugFragment")
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .lessEqual; depth.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depth)!
        depth.depthCompareFunction = .always; depth.isDepthWriteEnabled = false
        overlayDepthState = device.makeDepthStencilState(descriptor: depth)!
        super.init()
        let loader = MTKTextureLoader(device: device)
        for texture in RugTexture.allCases {
            guard let url = Bundle.main.url(forResource: texture.rawValue, withExtension: "png") else { throw RugRendererError.unavailable("The \(texture.title) texture is missing.") }
            textures[texture] = try loader.newTexture(URL: url, options: [.SRGB:true,.generateMipmaps:true,.textureUsage:MTLTextureUsage.shaderRead.rawValue])
        }
        buildMesh()
        view.delegate = self
        view.preferredFramesPerSecond = configuration.frameRate
    }

    func setSimulation(_ simulation: ClothSimulation) {
        self.simulation = simulation
        buildMesh(); lastTime = 0
    }

    func wake(_ view: MTKView) {
        simulation.wake(); lastTime = 0; fpsStart = 0; fpsFrames = 0
        view.enableSetNeedsDisplay = false; view.isPaused = false
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        lastTime = 0
        if view.isPaused { view.needsDisplay = true }
    }

    func draw(in view: MTKView) {
        let frameStart = CACurrentMediaTime()
        let elapsed = lastTime == 0 ? 1 / Float(configuration.frameRate) : Float(min(frameStart-lastTime,0.067))
        lastTime = frameStart
        let physicsStart = CACurrentMediaTime()
        _ = simulation.advance(elapsed: elapsed)
        physicsMilliseconds = (CACurrentMediaTime()-physicsStart)*1000
        onFrame?()
        guard inFlight.wait(timeout: .now()) == .success else { droppedFrames += 1; return }
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable, let command = queue.makeCommandBuffer() else { inFlight.signal(); return }
        bufferIndex = (bufferIndex+1)%vertexBuffers.count
        updateVertices()
        let vertexBuffer = vertexBuffers[bufferIndex]
        vertices.withUnsafeBytes { raw in _ = memcpy(vertexBuffer.contents(),raw.baseAddress!,raw.count) }
        var uniforms = RugUniforms(viewport: SIMD2(Float(view.bounds.width),Float(view.bounds.height)),origin: screenOrigin,options: SIMD2(configuration.highQualityShadows ? 1 : 0,0))
        encode(command: command,pass: pass,vertices: vertexBuffer,uniforms: &uniforms)
        let semaphore = inFlight
        command.addCompletedHandler { [weak self] buffer in
            semaphore.signal()
            let milliseconds = (buffer.gpuEndTime-buffer.gpuStartTime)*1000
            DispatchQueue.main.async { self?.gpuMilliseconds = milliseconds }
        }
        command.present(drawable); command.commit()
        frameCount += 1; fpsFrames += 1
        if fpsStart == 0 { fpsStart = frameStart }
        if frameStart-fpsStart >= 1 { actualFPS = Double(fpsFrames)/(frameStart-fpsStart); fpsStart=frameStart;fpsFrames=0 }
        frameMilliseconds = (CACurrentMediaTime()-frameStart)*1000
        if simulation.isSettled { onSettled?() }
    }

    private func buildMesh() {
        let sim = simulation, c = sim.columns, r = sim.rows
        boundary.removeAll(keepingCapacity: true); fringe.removeAll(keepingCapacity: true)
        for x in 0..<c-1 { boundary.append((x,x+1)) }
        for y in 0..<r-1 { boundary.append((y*c+c-1,(y+1)*c+c-1)) }
        for x in (1..<c).reversed() { boundary.append(((r-1)*c+x,(r-1)*c+x-1)) }
        for y in (1..<r).reversed() { boundary.append((y*c,(y-1)*c)) }
        for x in 0..<c-1 {
            for t: Float in [0.2,0.5,0.8] {
                fringe.append(FringeSegment(a:x,b:x+1,innerA:x+c,innerB:x+c+1,t:t))
                fringe.append(FringeSegment(a:(r-1)*c+x,b:(r-1)*c+x+1,innerA:(r-2)*c+x,innerB:(r-2)*c+x+1,t:t))
            }
        }
        vertices = [RugGPUVertex](repeating: RugGPUVertex(),count: sim.positions.count+boundary.count*4+fringe.count*4)
        normals = [SIMD3<Float>](repeating: .zero,count: sim.positions.count)
        meshIndices = sim.indices
        for offset in stride(from: sim.positions.count,to:vertices.count,by:4) {
            let o = UInt32(offset); meshIndices.append(contentsOf:[o,o+1,o+2,o+1,o+3,o+2])
        }
        indexBuffer = meshIndices.withUnsafeBytes { device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)! }
        vertexBuffers = (0..<3).map { _ in device.makeBuffer(length:vertices.count*MemoryLayout<RugGPUVertex>.stride,options:.storageModeShared)! }
    }

    private func updateVertices() {
        let positions = simulation.positions, indices = simulation.indices
        for i in normals.indices { normals[i] = .zero }
        for t in stride(from:0,to:indices.count,by:3) {
            let a=Int(indices[t]),b=Int(indices[t+1]),c=Int(indices[t+2])
            let n = simd_cross(positions[b]-positions[a],positions[c]-positions[a])
            normals[a] += n; normals[b] += n; normals[c] += n
        }
        for i in positions.indices {
            let normal = simd_length_squared(normals[i]) > 0.000001 ? simd_normalize(normals[i]) : SIMD3<Float>(0,0,1)
            normals[i] = normal
            vertices[i] = RugGPUVertex(position:positions[i],normal:normal,uv:simulation.uvs[i],material:0)
        }
        var o=positions.count
        for (a,b) in boundary {
            let pa=positions[a],pb=positions[b],edge=pb-pa
            let normal=simd_normalize(SIMD3(edge.y,-edge.x,0.01))
            vertices[o]=RugGPUVertex(position:pa,normal:normal,uv:simulation.uvs[a],material:1)
            vertices[o+1]=RugGPUVertex(position:pb,normal:normal,uv:simulation.uvs[b],material:1)
            vertices[o+2]=RugGPUVertex(position:pa-SIMD3(0,0,2),normal:normal,uv:simulation.uvs[a],material:1)
            vertices[o+3]=RugGPUVertex(position:pb-SIMD3(0,0,2),normal:normal,uv:simulation.uvs[b],material:1)
            o+=4
        }
        for thread in fringe {
            let point=simd_mix(positions[thread.a],positions[thread.b],SIMD3(repeating:thread.t))
            let inner=simd_mix(positions[thread.innerA],positions[thread.innerB],SIMD3(repeating:thread.t))
            let delta=point-inner
            let outward=simd_length_squared(delta)>0.00001 ? simd_normalize(delta) : SIMD3<Float>(0,1,0)
            let tangent=simd_normalize(positions[thread.b]-positions[thread.a])*0.65
            var end=point+outward*10
            end.z=max(0.6,end.z-1.0)
            vertices[o]=RugGPUVertex(position:point-tangent,normal:normals[thread.a],uv:.zero,material:2)
            vertices[o+1]=RugGPUVertex(position:point+tangent,normal:normals[thread.a],uv:.zero,material:2)
            vertices[o+2]=RugGPUVertex(position:end-tangent*0.60,normal:normals[thread.a],uv:.zero,material:2)
            vertices[o+3]=RugGPUVertex(position:end+tangent*0.60,normal:normals[thread.a],uv:.zero,material:2)
            o+=4
        }
    }

    private func encode(command: MTLCommandBuffer,pass: MTLRenderPassDescriptor,vertices buffer: MTLBuffer,uniforms: inout RugUniforms) {
        guard let encoder=command.makeRenderCommandEncoder(descriptor:pass) else { return }
        encoder.label="Woven cloth, contact shadow and fringe"
        encoder.setCullMode(.none)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setVertexBuffer(buffer,offset:0,index:0)
        encoder.setDepthStencilState(overlayDepthState)
        encoder.setRenderPipelineState(shadowPipeline)
        let offsets=configuration.highQualityShadows ? blurOffsets : [SIMD2<Float>.zero,SIMD2(2,-2),SIMD2(-2,2)]
        for offset in offsets {
            uniforms.shadowOffset=offset
            encoder.setVertexBytes(&uniforms,length:MemoryLayout<RugUniforms>.stride,index:1)
            encoder.setFragmentBytes(&uniforms,length:MemoryLayout<RugUniforms>.stride,index:1)
            encoder.drawIndexedPrimitives(type:.triangle,indexCount:simulation.indices.count,indexType:.uint32,indexBuffer:indexBuffer,indexBufferOffset:0)
        }
        encoder.setDepthStencilState(depthState)
        encoder.setRenderPipelineState(rugPipeline)
        uniforms.shadowOffset = .zero
        encoder.setVertexBytes(&uniforms,length:MemoryLayout<RugUniforms>.stride,index:1)
        encoder.setFragmentTexture(textures[configuration.texture],index:0)
        encoder.drawIndexedPrimitives(type:.triangle,indexCount:meshIndices.count,indexType:.uint32,indexBuffer:indexBuffer,indexBufferOffset:0)
        if configuration.debugCollisions && !simulation.collisions.mounds.isEmpty {
            let volumes=simulation.collisions.mounds.prefix(64).map { DebugGPUVolume(centerExtent:SIMD4($0.center.x,$0.center.y,$0.halfExtent.x,$0.halfExtent.y),height:SIMD4($0.height,0,0,0)) }
            encoder.setRenderPipelineState(debugPipeline);encoder.setDepthStencilState(overlayDepthState)
            volumes.withUnsafeBytes { encoder.setVertexBytes($0.baseAddress!,length:$0.count,index:0) }
            encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:6,instanceCount:volumes.count)
        }
        encoder.endEncoding()
    }

    func capture(to url: URL) throws {
        updateVertices()
        var lower=SIMD2<Float>(repeating:.infinity),upper=SIMD2<Float>(repeating:-.infinity)
        for p in simulation.positions { let xy=ClothGeometry.project(p);lower=simd_min(lower,xy);upper=simd_max(upper,xy) }
        let viewport=upper-lower+SIMD2(repeating:90)
        let width=Int(ceil(viewport.x))*2,height=Int(ceil(viewport.y))*2
        let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm_srgb,width:width,height:height,mipmapped:false)
        descriptor.usage=[.renderTarget];descriptor.storageMode = .shared
        guard let texture=device.makeTexture(descriptor:descriptor),let command=queue.makeCommandBuffer() else { throw RugRendererError.unavailable("Could not allocate a capture target.") }
        descriptor.pixelFormat = .depth32Float;descriptor.storageMode = .private
        let pass=MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture=texture;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0)
        pass.depthAttachment.texture=device.makeTexture(descriptor:descriptor);pass.depthAttachment.loadAction = .clear;pass.depthAttachment.clearDepth=1
        let buffer=vertices.withUnsafeBytes { device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)! }
        var uniforms=RugUniforms(viewport:viewport,origin:lower-SIMD2(repeating:45),options:SIMD2(configuration.highQualityShadows ? 1 : 0,0))
        encode(command:command,pass:pass,vertices:buffer,uniforms:&uniforms)
        command.commit();command.waitUntilCompleted()
        if let error=command.error { throw error }
        var data=Data(count:width*height*4)
        data.withUnsafeMutableBytes { texture.getBytes($0.baseAddress!,bytesPerRow:width*4,from:MTLRegionMake2D(0,0,width,height),mipmapLevel:0) }
        guard let provider=CGDataProvider(data:data as CFData),let cgImage=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent),let png=NSBitmapImageRep(cgImage:cgImage).representation(using:.png,properties:[:]) else { throw RugRendererError.unavailable("Could not encode the capture.") }
        try png.write(to:url)
    }
}
