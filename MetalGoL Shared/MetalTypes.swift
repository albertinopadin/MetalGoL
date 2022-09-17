//
//  MetalTypes.swift
//  MetalGoL
//
//  Created by Albertino Padin on 9/17/22.
//

import simd

typealias float2 = SIMD2<Float>
typealias float3 = SIMD3<Float>
typealias float4 = SIMD4<Float>

protocol sizeable { }

extension sizeable {
    static var size: Int {
        return MemoryLayout<Self>.size
    }
    
    static var stride: Int {
        return MemoryLayout<Self>.stride
    }
    
    static func size(_ count: Int) -> Int {
        return MemoryLayout<Self>.size * count
    }
    
    static func stride(_ count: Int) -> Int {
        return MemoryLayout<Self>.stride * count
    }
}

extension UInt32: sizeable {}
extension Int32: sizeable {}
extension Float: sizeable {}
extension SIMD2: sizeable {}
extension SIMD3: sizeable {}
extension SIMD4: sizeable {}

struct Vertex: sizeable {
    var position: float3
    var normal: float3 = float3(0, 0, 1)
}
