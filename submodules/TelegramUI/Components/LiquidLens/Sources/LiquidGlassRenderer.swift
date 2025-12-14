import MetalKit
import LiquidLensSharedTypes

private final class BundleMarker: NSObject {
}

private var metalLibraryValue: MTLLibrary?
private func metalLibrary(device: MTLDevice) -> MTLLibrary? {
    if let metalLibraryValue {
        return metalLibraryValue
    }
    
    let mainBundle = Bundle(for: BundleMarker.self)
    guard let path = mainBundle.path(forResource: "LiquidLensMetalSourcesBundle", ofType: "bundle") else {
        return nil
    }
    guard let bundle = Bundle(path: path) else {
        return nil
    }
    guard let library = try? device.makeDefaultLibrary(bundle: bundle) else {
        return nil
    }
    
    metalLibraryValue = library
    return library
}

final class LiquidGlassRenderer: NSObject, MTKViewDelegate {
    
    private let device: MTLDevice
    private let pixelFormat: MTLPixelFormat
    private let commandQueue: MTLCommandQueue
    
    private let pipelineMain: MTLRenderPipelineState
    private let pipelineBG: MTLRenderPipelineState
    private let pipelineVBlur: MTLRenderPipelineState
    private let pipelineHBlur: MTLRenderPipelineState
    
    private let sampler: MTLSamplerState
    private let vertexBuffer: MTLBuffer
    
    private var argumentsBuffer: MTLBuffer?
    private var weightsBuffer: MTLBuffer?
    
    private var backgroundPassTexture: MTLTexture?
    private var verticalBlurTexture: MTLTexture?
    private var horizontalBlurTexture: MTLTexture?
    
    private var drawableSize: CGSize = .zero
    private var cachedBlurRadius: Int = -1
    
    private var arguments: LiquidGlassArguments = .default()
    private var blurRadius: Int = 1
    
    var backgroundTexture: MTLTexture?
    var backgroundOverlayTexture: MTLTexture?
    
    init(with device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm) throws {
        self.device = device
        self.pixelFormat = pixelFormat
        
        guard let queue = device.makeCommandQueue() else {
            throw NSError(domain: "LiquidGlassRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "No command queue"])
        }
        self.commandQueue = queue
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD2<Float>>.stride * 2
        
        func makePipeline(fragment: String) throws -> MTLRenderPipelineState {
            guard
                let library = metalLibrary(device: device),
                let v = library.makeFunction(name: "liquidGlassVertex"),
                let f = library.makeFunction(name: fragment)
            else {
                throw NSError(domain: "LiquidGlassRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing shader functions for \(fragment)"])
            }
            let pipelineDesc = MTLRenderPipelineDescriptor()
            pipelineDesc.vertexDescriptor = vertexDescriptor
            pipelineDesc.vertexFunction = v
            pipelineDesc.fragmentFunction = f
            pipelineDesc.colorAttachments[0].pixelFormat = pixelFormat
            return try device.makeRenderPipelineState(descriptor: pipelineDesc)
        }
        
        self.pipelineMain = try makePipeline(fragment: "liquidGlassFragment")
        self.pipelineBG = try makePipeline(fragment: "bgFragment")
        self.pipelineVBlur = try makePipeline(fragment: "vBlurFragment")
        self.pipelineHBlur = try makePipeline(fragment: "hBlurFragment")
        
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDesc) else {
            throw NSError(domain: "LiquidGlassRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Sampler creation failed"])
        }
        self.sampler = sampler
        
        let quad: [SIMD4<Float>] = [
            SIMD4<Float>(-1, -1, -1, -1),
            SIMD4<Float>(1, -1, 1, -1),
            SIMD4<Float>(-1, 1, -1, 1),
            SIMD4<Float>(1, 1, 1, 1),
        ]
        guard let vb = device.makeBuffer(bytes: quad, length: quad.count * MemoryLayout<SIMD4<Float>>.stride, options: []) else {
            throw NSError(domain: "LiquidGlassRenderer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Vertex buffer failed"])
        }
        self.vertexBuffer = vb
    }
    
    // MARK: - Private
    
    private func makeRenderTarget(width: Int, height: Int, label: String) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat,
                                                            width: width,
                                                            height: height,
                                                            mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        let texture = device.makeTexture(descriptor: desc)
        texture?.label = label
        return texture
    }
    
    private func makeGaussianWeights(radius: Int) -> [Float] {
        let sigma = Float(radius) / 3.0
        var kernel: [Float] = []
        var sum: Float = 0
        for i in 0...radius {
            let weight = exp(-0.5 * (Float(i * i)) / (sigma * sigma))
            kernel.append(weight)
            sum += i == 0 ? weight : weight * 2
        }
        return kernel.map { $0 / sum }
    }
    
    private func updateWeightsBuffer(for radius: Int) {
        guard cachedBlurRadius != radius || weightsBuffer == nil else { return }
        let weights = makeGaussianWeights(radius: radius)
        let length = MemoryLayout<Float>.stride * weights.count
        if weightsBuffer == nil || weightsBuffer?.length ?? 0 < length {
            weightsBuffer = device.makeBuffer(length: length, options: .storageModeShared)
        }
        if let destination = weightsBuffer?.contents() {
            weights.withUnsafeBytes { bytes in
                destination.copyMemory(from: bytes.baseAddress!, byteCount: length)
            }
        }
        cachedBlurRadius = radius
    }
    
    private func rebuildRenderTargetsIfNeeded() {
        guard drawableSize.width > 0, drawableSize.height > 0 else {
            backgroundPassTexture = nil
            verticalBlurTexture = nil
            horizontalBlurTexture = nil
            return
        }
        
        let width = Int(drawableSize.width)
        let height = Int(drawableSize.height)
        
        func needsRebuild(_ texture: MTLTexture?) -> Bool {
            texture?.width != width || texture?.height != height
        }
        
        if needsRebuild(backgroundPassTexture) {
            backgroundPassTexture = makeRenderTarget(width: width, height: height, label: "Background Pass")
        }
        if needsRebuild(verticalBlurTexture) {
            verticalBlurTexture = makeRenderTarget(width: width, height: height, label: "Vertical Blur Pass")
        }
        if needsRebuild(horizontalBlurTexture) {
            horizontalBlurTexture = makeRenderTarget(width: width, height: height, label: "Horizontal Blur Pass")
        }
    }
    
    // MARK: - API
    
    func loadTexture(from image: CGImage) throws -> MTLTexture {
        let loader = MTKTextureLoader(device: device)
        return try loader.newTexture(cgImage: image, options: [.SRGB: false])
    }
    
    func update(view: MTKView, backgroundTexture: MTLTexture, backgroundOverlayTexture: MTLTexture?, arguments: LiquidGlassArguments) {
        if view.colorPixelFormat != pixelFormat {
            view.colorPixelFormat = pixelFormat
        }
        self.backgroundTexture = backgroundTexture
        self.backgroundOverlayTexture = backgroundOverlayTexture
        self.arguments = arguments
        let requestedBlurRadius = Int(arguments.blurRadius)
        blurRadius = max(0, min(requestedBlurRadius, 64))
        self.arguments.blurRadius = Int32(blurRadius)
        drawableSize = view.drawableSize
        rebuildRenderTargetsIfNeeded()
        updateWeightsBuffer(for: blurRadius)
        updateArgumentsBuffer(for: view)
        view.setNeedsDisplay()
    }
    
    private func updateArgumentsBuffer(for view: MTKView) {
        guard drawableSize.width > 0, drawableSize.height > 0 else { return }
        
        let resolution = SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
        let dpr = Float(view.contentScaleFactor)
        
        var arguments = self.arguments
        arguments.resolution = resolution
        arguments.dpr = dpr
        if arguments.contentSize.x == 0 || arguments.contentSize.y == 0 {
            arguments.contentOrigin = .zero
            arguments.contentSize = resolution
        }
        if arguments.shapeWidth == 0 || arguments.shapeHeight == 0 {
            let shapeSize = 0.2 * min(resolution.x, resolution.y) / dpr
            arguments.shapeWidth = shapeSize
            arguments.shapeHeight = shapeSize
        }
        if let bgTexture = backgroundTexture {
            arguments.bgTextureRatio = Float(bgTexture.width) / Float(bgTexture.height)
            arguments.bgTextureReady = 1
        } else {
            arguments.bgTextureReady = 0
        }
        arguments.blurRadius = Int32(blurRadius)
        self.arguments = arguments
        
        let length = MemoryLayout<LiquidGlassArguments>.stride
        if argumentsBuffer == nil || argumentsBuffer?.length ?? 0 < length {
            argumentsBuffer = device.makeBuffer(length: length, options: .storageModeShared)
        }
        if let pointer = argumentsBuffer?.contents() {
            memcpy(pointer, &arguments, length)
        }
    }
    
    private func makePassDescriptor(for texture: MTLTexture) -> MTLRenderPassDescriptor {
        let rpd = MTLRenderPassDescriptor()
        let colorAttachment = rpd.colorAttachments[0]
        colorAttachment?.texture = texture
        colorAttachment?.loadAction = .dontCare
        colorAttachment?.storeAction = .store
        return rpd
    }
    
    private func encodeBackgroundPass(_ commandBuffer: MTLCommandBuffer, texture: MTLTexture, bgTexture: MTLTexture, bgOverlayTexture: MTLTexture?) {
        guard let argumentsBuffer = argumentsBuffer,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: makePassDescriptor(for: texture)) else { return }
        
        encoder.setRenderPipelineState(pipelineBG)
        encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(texture.width), height: Double(texture.height), znear: 0, zfar: 1))
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(bgTexture, index: 0)
        encoder.setFragmentTexture(bgOverlayTexture, index: 1)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBuffer(argumentsBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }
    
    private func encodeBlurPass(_ commandBuffer: MTLCommandBuffer, pipeline: MTLRenderPipelineState, input: MTLTexture, output: MTLTexture) {
        guard let argumentsBuffer = argumentsBuffer,
              let weightsBuffer = weightsBuffer,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: makePassDescriptor(for: output)) else { return }
        
        encoder.setRenderPipelineState(pipeline)
        encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(output.width), height: Double(output.height), znear: 0, zfar: 1))
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(input, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBuffer(argumentsBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(weightsBuffer, offset: 0, index: 2)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }
    
    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawableSize = size
        rebuildRenderTargetsIfNeeded()
    }
    
    func draw(in view: MTKView) {
        if drawableSize != view.drawableSize {
            drawableSize = view.drawableSize
            rebuildRenderTargetsIfNeeded()
        }
        
        updateWeightsBuffer(for: blurRadius)
        updateArgumentsBuffer(for: view)
        
        guard
            let bgTexture = backgroundTexture,
            let backgroundPassTexture,
            let verticalBlurTexture,
            let horizontalBlurTexture,
            let argumentsBuffer = argumentsBuffer
        else { return }
        
        guard weightsBuffer != nil else { return }
        
        guard
            let finalDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }
        
        commandBuffer.label = "LiquidGlass Command Buffer"
        
        encodeBackgroundPass(commandBuffer, texture: backgroundPassTexture, bgTexture: bgTexture, bgOverlayTexture: backgroundOverlayTexture)
        encodeBlurPass(commandBuffer, pipeline: pipelineVBlur, input: backgroundPassTexture, output: verticalBlurTexture)
        encodeBlurPass(commandBuffer, pipeline: pipelineHBlur, input: verticalBlurTexture, output: horizontalBlurTexture)
        
        if let colorAttachment = finalDescriptor.colorAttachments[0] {
            colorAttachment.clearColor = view.clearColor
            colorAttachment.loadAction = .clear
            colorAttachment.storeAction = .store
        }
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: finalDescriptor) else {
            commandBuffer.commit()
            return
        }
        
        encoder.setRenderPipelineState(pipelineMain)
        encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(drawableSize.width), height: Double(drawableSize.height), znear: 0, zfar: 1))
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(horizontalBlurTexture, index: 0)
        encoder.setFragmentTexture(backgroundPassTexture, index: 1)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBuffer(argumentsBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
