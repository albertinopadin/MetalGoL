//
//  Node.swift
//  MetalGoL
//
//  Created by Albertino Padin on 8/6/22.
//

import MetalKit

public final class Node {
    public var color = SIMD4<Float>(1, 1, 1, 1)
    public var transform: simd_float4x4 = matrix_identity_float4x4
    
    init() { }
    
    init(position: SIMD3<Float>, color: SIMD4<Float>, alpha: Float) {
        self.transform = float4x4(translate: SIMD3<Float>(position.x, position.y, position.z))
        self.color = color
        self.alpha = alpha
    }
    
    @inlinable
    var alpha: Float {
        get {
            return color.w
        }
        
        set {
            color.w = newValue
        }
    }
    
    @inlinable
    var position: SIMD3<Float> {
        return worldTransform.columns.3.xyz
    }
    
    @inlinable
    var worldTransform: simd_float4x4 {
        return transform
    }
}
