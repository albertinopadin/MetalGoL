//
//  Renderer.swift
//  MetalGoL
//
//  Created by Albertino Padin on 8/6/22.
//

import Metal
import MetalKit


let MaxOutstandingFrameCount = 3
let MaxConstantsSize = 1_024 * 1_024 * 256
let MinBufferAlignment = 256

struct NodeConstants {
    var modelMatrix: float4x4
    var color: SIMD4<Float>
}

struct LightConstants {
    var viewProjectionMatrix: float4x4
    var intensity: simd_float3
    var position: simd_float3
    var direction: simd_float3
    var type: UInt32
}

struct FrameConstants {
    var projectionMatrix: float4x4
    var viewMatrix: float4x4
    var inverseViewDirectionMatrix: float3x3
    var lightCount: UInt32
}

struct InstanceConstants {
    var modelMatrix: float4x4
    var color: simd_float4
}


final class Renderer: NSObject, MTKViewDelegate {
    private static let DefaultProjectionFrameNear: Float = 0.01
    private static let DefaultProjectionFrameFar: Float = 500
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let view: MTKView
    
    let pointOfView = Node()
    var lights = [Light]()
    
    private var vertexDescriptor: MTLVertexDescriptor!
    private var mdlVertexDescriptor: MDLVertexDescriptor!
    
    private var renderPipelineState: MTLRenderPipelineState!
    
    private var constantBuffer: MTLBuffer!
    private var currentConstantBufferOffset = 0
    private var frameConstantsOffset: Int = 0
    private var lightConstantsOffset: Int = 0
    private var nodeConstantsOffsets = [Int]()
    
    private var frameSemaphore = DispatchSemaphore(value: MaxOutstandingFrameCount)
    private var frameIndex = 0
    private var time: TimeInterval = 0
    
    private let nearClip: Float
    private let farClip: Float
    
    private let updateQueue = DispatchQueue(label: "metalgol.update.queue",
                                            qos: .userInteractive)
    
    let gridSize = 500
    public var grid: Grid!
    let cellShape = CellShape.Square
    
    private var constantsBufferSize: Int = 0
    
    init(device: MTLDevice,
         view: MTKView,
         nearClip: Float = DefaultProjectionFrameNear,
         farClip: Float = DefaultProjectionFrameFar) {
        view.device = device
        self.device = device
        self.view = view
        self.nearClip = nearClip
        self.farClip = farClip
        self.commandQueue = device.makeCommandQueue()!
        
        super.init()
        
        view.device = device
        view.delegate = self
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        
        makeScene()
        makeResources(numCells: grid.cells.count)
        makePipeline()
    }
    
    func makeScene() {
        mdlVertexDescriptor = createMDLVertexDescriptor()
        
        vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mdlVertexDescriptor)!
        
        let mdlAllocator = MTKMeshBufferAllocator(device: device)
        
        grid = Grid(gridSize, gridSize,
                    device: device,
                    allocator: mdlAllocator,
                    vertexDescriptor: mdlVertexDescriptor,
                    shape: cellShape)
        grid.randomState(liveProbability: Grid.DefaultLiveProbability)
        print("Number of nodes: \(grid.cells.count)")
        
        let ambientLight = Light()
        ambientLight.type = .ambient
        ambientLight.intensity = 1.0
        lights.append(ambientLight)
    }
    
    func createMDLVertexDescriptor() -> MDLVertexDescriptor {
        let mdlVD = MDLVertexDescriptor()
        mdlVD.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition,
                                                 format: .float3,
                                                 offset: 0,
                                                 bufferIndex: 0)
        mdlVD.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal,
                                                 format: .float3,
                                                 offset: 12,
                                                 bufferIndex: 0)
        mdlVD.layouts[0] = MDLVertexBufferLayout(stride: 24)
        return mdlVD
    }
    
    func makeResources(numCells: Int) {
        let instanceConstantsSize = numCells * MemoryLayout<InstanceConstants>.self.stride
        let frameConstantsSize = MemoryLayout<FrameConstants>.self.stride
        let lightConstantsSize = lights.count * MemoryLayout<LightConstants>.self.stride
        constantsBufferSize = (instanceConstantsSize + frameConstantsSize + lightConstantsSize)
        constantsBufferSize *= (MaxOutstandingFrameCount + 1)
        print("constantsBufferSize (in MB): \(constantsBufferSize / (1024 * 1024))")
        constantBuffer = device.makeBuffer(length: constantsBufferSize, options: .storageModeShared)
//        constantBuffer = device.makeBuffer(length: constantBufferLength, options: .storageModeManaged)
        constantBuffer.label = "Dynamic Constants Buffer"
    }
    
    func makePipeline() {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Unable to create default Metal library")
        }
        
        let renderPipelineDescriptor = MTLRenderPipelineDescriptor()
        renderPipelineDescriptor.vertexDescriptor = vertexDescriptor
        renderPipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        renderPipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        renderPipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        
        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
        } catch {
            fatalError("Error while creating render pipeline state: \(error)")
        }
    }
    
    func allocateConstantStorage(size: Int, alignment: Int) -> Int {
        let effectiveAlignment = lcm(alignment, MinBufferAlignment)
        var allocationOffset = align(currentConstantBufferOffset, upTo: effectiveAlignment)
        if (allocationOffset + size >= constantsBufferSize) {
            allocationOffset = 0
        }
        currentConstantBufferOffset = allocationOffset + size
        return allocationOffset
    }
    
    func updateFrameConstants() {
        let aspectRatio = Float(view.drawableSize.width / view.drawableSize.height)
        let projectionMatrix = simd_float4x4(perspectiveProjectionFoVY: .pi / 3,
                                             aspectRatio: aspectRatio,
                                             near: nearClip,
                                             far: farClip)
        
        let cameraMatrix = pointOfView.worldTransform
        let viewMatrix = cameraMatrix.inverse
        var viewDirectionMatrix = viewMatrix
        viewDirectionMatrix.columns.3 = SIMD4<Float>(0, 0, 0, 1)
        
        var constants = FrameConstants(projectionMatrix: projectionMatrix,
                                       viewMatrix: viewMatrix,
                                       inverseViewDirectionMatrix: viewDirectionMatrix.inverse.upperLeft3x3,
                                       lightCount: UInt32(lights.count))
        
        let layout = MemoryLayout<FrameConstants>.self
        frameConstantsOffset = allocateConstantStorage(size: layout.size, alignment: layout.stride)
        let constantsPointer = constantBuffer.contents().advanced(by: frameConstantsOffset)
        constantsPointer.copyMemory(from: &constants, byteCount: layout.size)
    }
    
    func updateLightConstants() {
        let layout = MemoryLayout<LightConstants>.self
        lightConstantsOffset = allocateConstantStorage(size: layout.stride * lights.count, alignment: layout.stride)
        let lightsBufferPointer = constantBuffer.contents()
            .advanced(by: lightConstantsOffset)
            .assumingMemoryBound(to: LightConstants.self)
        
        for (lightIndex, light) in lights.enumerated() {
            let shadowViewMatrix = light.worldTransform.inverse
            let shadowProjectionMatrix = light.projectionMatrix
            let shadowViewProjectionMatrix = shadowProjectionMatrix * shadowViewMatrix
            lightsBufferPointer[lightIndex] = LightConstants(viewProjectionMatrix: shadowViewProjectionMatrix,
                                                             intensity: light.color * light.intensity,
                                                             position: light.position,
                                                             direction: light.direction,
                                                             type: light.type.rawValue)
        }
    }
    
    func updateNodeConstants(timestep: Float) {
        // Update node color here
        nodeConstantsOffsets.removeAll()

        let layout = MemoryLayout<InstanceConstants>.self
        let offset = allocateConstantStorage(size: layout.stride * grid.cells.count, alignment: layout.stride)
        let instanceConstants = constantBuffer.contents().advanced(by: offset).bindMemory(to: InstanceConstants.self,
                                                                                          capacity: grid.cells.count)
        
        let t_writeBuffer = timeit {
            updateQueue.sync {
                grid.cells.withUnsafeBufferPointer { buffer in
                    DispatchQueue.concurrentPerform(iterations: self.gridSize) { x in
                        DispatchQueue.concurrentPerform(iterations: self.gridSize) { y in
                            let i = x + (y * self.gridSize)
                            instanceConstants[i] = InstanceConstants(modelMatrix: buffer[i].transform,
                                                                     color: buffer[i].color)
                        }
                    }
                }
            }
        }
    
        nodeConstantsOffsets.append(offset)
        
        print("[updateNodeConstants] Writing instance constants time: \(Double(t_writeBuffer)/1_000_000) ms")
    }
    
    func renderPassDescriptor(colorTexture: MTLTexture) -> MTLRenderPassDescriptor {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = colorTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = view.clearColor
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        return renderPassDescriptor
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // TODO if implement MSAA
    }
    
    func draw(in view: MTKView) {
        let t_totalDraw = timeit {
            // This blocks if 3 frames are already underway:
            frameSemaphore.wait()
            
            let initialConstantOffset = currentConstantBufferOffset
            let timestep = 1.0 / Double(view.preferredFramesPerSecond)
            time += timestep
            
            let t_constants = timeit {
                updateLightConstants()
                updateFrameConstants()
                let t_nodeConstants = timeit {
                    updateNodeConstants(timestep: Float(timestep))
                }
                print("Run time for updating Node constants: \(Double(t_nodeConstants)/1_000_000) ms")
            }
            print("Run time for updating constants: \(Double(t_constants)/1_000_000) ms")
            
            guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
            
            guard let drawable = view.currentDrawable else { return }
            let renderPassDescriptor = renderPassDescriptor(colorTexture: drawable.texture)
            
            let t_main = timeit {
                // Main pass:
                // TODO: Can I pull this (makeRenderCommandEncoder) out of the draw loop?
                let renderCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
                renderCommandEncoder.setFrontFacing(.counterClockwise)
                renderCommandEncoder.setCullMode(.back)
                renderCommandEncoder.setRenderPipelineState(renderPipelineState)
                
                // Bind constants:
                renderCommandEncoder.setVertexBuffer(constantBuffer, offset: frameConstantsOffset, index: 3)
                renderCommandEncoder.setFragmentBuffer(constantBuffer, offset: frameConstantsOffset, index: 3)
                renderCommandEncoder.setFragmentBuffer(constantBuffer, offset: lightConstantsOffset, index: 4)
                
                renderCommandEncoder.setVertexBuffer(constantBuffer, offset: nodeConstantsOffsets[0], index: 2)
                
                let t_main_loop = timeit {
                    let mesh = grid.cellMesh
                    
                    for (i, meshBuffer) in mesh.vertexBuffers.enumerated() {
                        renderCommandEncoder.setVertexBuffer(meshBuffer.buffer, offset: meshBuffer.offset, index: i)
                    }

                    for submesh in mesh.submeshes {
                        let indexBuffer = submesh.indexBuffer
                        renderCommandEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                                   indexCount: submesh.indexCount,
                                                                   indexType: submesh.indexType,
                                                                   indexBuffer: indexBuffer.buffer,
                                                                   indexBufferOffset: indexBuffer.offset,
                                                                   instanceCount: grid.cells.count)
                    }
                }
                
                print("Run time for main draw pass loop: \(Double(t_main_loop)/1_000_000) ms")
                
                renderCommandEncoder.endEncoding()
                // END main pass
            }
            print("Run time for main draw pass: \(Double(t_main)/1_000_000) ms")
            
            commandBuffer.present(drawable)
            commandBuffer.addCompletedHandler { [weak self] _ in
                self?.frameSemaphore.signal()
            }
            commandBuffer.commit()
            
            let constantSize = currentConstantBufferOffset - initialConstantOffset
            if (constantSize > constantsBufferSize / MaxOutstandingFrameCount) {
                print("Insufficient constant storage: frame consumed \(constantSize) bytes of total \(constantsBufferSize) bytes")
            }
            
            frameIndex += 1
        }
        print("Total Draw call Run Time: \(Double(t_totalDraw)/1_000_000) ms")
    }
}

