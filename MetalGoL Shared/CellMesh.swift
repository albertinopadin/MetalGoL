//
//  CellMesh.swift
//  MetalGoL
//
//  Created by Albertino Padin on 9/16/22.
//

import MetalKit

enum CellMeshType {
    case Quad
    case Box
    case Sphere
}

struct CellVertexBuffer {
    let buffer: MTLBuffer
    let offset: Int
}

struct CellSubmesh {
    public var primitiveType: MTLPrimitiveType = .triangle
    public var indexCount: Int
    public var indexType: MTLIndexType = .uint32
    public var indexBuffer: MTLBuffer
    public var indexBufferOffset: Int
}

class CellMesh {
    public var vertexBuffers: [CellVertexBuffer]
    public var submeshes: [CellSubmesh]
    
    init(type: CellMeshType,
         size: Float,
         device: MTLDevice,
         allocator: MDLMeshBufferAllocator,
         vertexDescriptor: MDLVertexDescriptor) {
        switch type {
            case .Quad:
                let vertices = CellMesh.makeQuadVertices(size: size)
                let mtlVertexBuffer = device.makeBuffer(bytes: vertices, length: Vertex.stride(vertices.count), options: [])!
                mtlVertexBuffer.label = "Vertex Buffer"
                vertexBuffers = [CellVertexBuffer(buffer: mtlVertexBuffer, offset: 0)]
                // Counterclockwise:
                let indices: [UInt32] = [
                    0, 1, 2,
                    0, 2, 3
                ]
                let mtlIndexBuffer = device.makeBuffer(bytes: indices, length: UInt32.stride(indices.count), options: [])!
                mtlIndexBuffer.label = "Index Buffer"
                submeshes = [CellSubmesh(indexCount: indices.count, indexBuffer: mtlIndexBuffer, indexBufferOffset: 0)]
            case .Box:
                let mesh = CellMesh.makeBoxMtkMesh(device: device,
                                                   allocator: allocator,
                                                   vertexDescriptor: vertexDescriptor,
                                                   size: size)
                vertexBuffers = CellMesh.makeVertexBuffers(mtkMesh: mesh)
                submeshes = CellMesh.makeSubmeshes(mtkMesh: mesh)
            case .Sphere:
                let mesh = CellMesh.makeSphereMtkMesh(device: device,
                                                      allocator: allocator,
                                                      vertexDescriptor: vertexDescriptor,
                                                      size: size)
                vertexBuffers = CellMesh.makeVertexBuffers(mtkMesh: mesh)
                submeshes = CellMesh.makeSubmeshes(mtkMesh: mesh)
        }
    }
    
    static func makeQuadVertices(size: Float) -> [Vertex] {
        let halfSize    = size / 2
        let topRight    = Vertex(position: float3(halfSize, halfSize, 0))
        let topLeft     = Vertex(position: float3(-halfSize, halfSize, 0))
        let bottomLeft  = Vertex(position: float3(-halfSize, -halfSize, 0))
        let bottomRight = Vertex(position: float3(halfSize, -halfSize, 0))
        return [topRight, topLeft, bottomLeft, bottomRight]
    }
    
    static func makeVertexBuffers(mtkMesh: MTKMesh) -> [CellVertexBuffer] {
        var cVertexBuffers = [CellVertexBuffer]()
        for mtkMeshBuffer in mtkMesh.vertexBuffers {
            let cvb = CellVertexBuffer(buffer: mtkMeshBuffer.buffer, offset: mtkMeshBuffer.offset)
            cVertexBuffers.append(cvb)
        }
        return cVertexBuffers
    }
    
    static func makeSubmeshes(mtkMesh: MTKMesh) -> [CellSubmesh] {
        var cSubmeshes = [CellSubmesh]()
        for submesh in mtkMesh.submeshes {
            let iBuf = submesh.indexBuffer
            let cSubmesh = CellSubmesh(primitiveType: submesh.primitiveType,
                                       indexCount: submesh.indexCount,
                                       indexType: submesh.indexType,
                                       indexBuffer: iBuf.buffer,
                                       indexBufferOffset: iBuf.offset)
            cSubmeshes.append(cSubmesh)
        }
        return cSubmeshes
    }
    
    static func makeBoxMtkMesh(device: MTLDevice,
                               allocator: MDLMeshBufferAllocator,
                               vertexDescriptor: MDLVertexDescriptor,
                               size: Float) -> MTKMesh {
        let mdlBoxMesh = MDLMesh(boxWithExtent: SIMD3<Float>(size, size, 0.01),
                                 segments: SIMD3<UInt32>(1, 1, 1),
                                 inwardNormals: false,
                                 geometryType: .triangles,
                                 allocator: allocator)
        mdlBoxMesh.vertexDescriptor = vertexDescriptor
        let boxMesh = try! MTKMesh(mesh: mdlBoxMesh, device: device)
        return boxMesh
    }
    
    static func makeSphereMtkMesh(device: MTLDevice,
                                  allocator: MDLMeshBufferAllocator,
                                  vertexDescriptor: MDLVertexDescriptor,
                                  size: Float) -> MTKMesh {
        let mdlSphere = MDLMesh(sphereWithExtent: SIMD3<Float>(size, size, size),
                                segments: SIMD2<UInt32>(8, 8),
                                inwardNormals: false,
                                geometryType: .triangles,
                                allocator: allocator)
        mdlSphere.vertexDescriptor = vertexDescriptor
        let sphereMesh = try! MTKMesh(mesh: mdlSphere, device: device)
        return sphereMesh
    }
}
