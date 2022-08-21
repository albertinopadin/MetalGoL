//
//  Cell.swift
//  MetalGoL
//
//  Created by Albertino Padin on 8/7/22.
//

import Metal
import MetalKit


public struct CellAlpha {
    public static let live: Float = 1.0
    public static let dead: Float = 0.0
}

public enum CellShape {
    case Square, Circle
}


public final class Cell {
    public static let squareNodeSize: Float = 0.92
    public static let circleNodeSize: Float = 0.4
    
    public final var currentState: Bool
    public final var nextState: Bool
    public final var alive: Bool
    
    public final var neighbors: ContiguousArray<Cell>
    public final var liveNeighbors: Int = 0
    
    public var color = SIMD4<Float>(1, 1, 1, 1)
    public var transform: simd_float4x4 = matrix_identity_float4x4
    
    public var position: SIMD3<Float> {
        get {
            return transform.columns.3.xyz
        }
        
        set {
            transform = float4x4(translate: SIMD3<Float>(newValue.x, newValue.y, newValue.z))
        }
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
    
    public init(color: SIMD4<Float>,
                position: SIMD3<Float>,
                alive: Bool = false) {
        self.currentState = alive
        self.nextState = self.currentState
        self.neighbors = ContiguousArray<Cell>()
        self.alive = alive
        self.color = color
        self.position = position
    }
    
    @inlinable
    public final func makeLive() {
        setState(live: true)
        alpha = CellAlpha.live
    }
    
    @inlinable
    public final func makeDead() {
        setState(live: false)
        alpha = CellAlpha.dead
    }
    
    @inlinable
    public final func setState(live: Bool) {
        currentState = live
        alive = currentState
        nextState = currentState
    }
    
    @inlinable
    public final func prepareUpdate() {
        // Lazy helps tremendously as it prevents an intermediate result array from being created
        // For some reason doing this directly is faster than calling the extension:
        liveNeighbors = neighbors.lazy.filter({ $0.alive }).count
        
        if !(!currentState && liveNeighbors < 3) {
            nextState = (currentState && liveNeighbors == 2) || (liveNeighbors == 3)
        }
    }
    
    @inlinable
    public final func update() {
        if needsUpdate() {
            if nextState {
                makeLive()
            } else {
                makeDead()
            }
        }
    }
    
    @inlinable
    public final func needsUpdate() -> Bool {
        return currentState != nextState
    }
}
