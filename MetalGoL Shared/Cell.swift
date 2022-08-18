//
//  Cell.swift
//  MetalGoL
//
//  Created by Albertino Padin on 8/7/22.
//

import Metal
import MetalKit

public enum CellState {
    case Live, Dead
}

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
    
    public final var currentState: CellState
    public final var nextState: CellState
    public final var alive: Bool
    
    public final var neighbors: ContiguousArray<Cell>
    public final var liveNeighbors: Int = 0
    
    public final let node: Node
    
    public var position: SIMD3<Float> {
        get {
            return node.position
        }
        
        set {
            node.transform = float4x4(translate: SIMD3<Float>(newValue.x, newValue.y, newValue.z))
        }
    }
    
    public init(color: SIMD4<Float>,
                position: SIMD3<Float>,
                alive: Bool = false) {
        self.currentState = alive ? .Live: .Dead
        self.nextState = self.currentState
        self.neighbors = ContiguousArray<Cell>()
        self.alive = alive
        self.node = Node(position: position, color: color, alpha: CellAlpha.live)
    }
    
    @inlinable
    public final func makeLive() {
        setState(state: .Live)
        node.alpha = CellAlpha.live
    }
    
    @inlinable
    public final func makeDead() {
        setState(state: .Dead)
        node.alpha = CellAlpha.dead
    }
    
    @inlinable
    public final func setState(state: CellState) {
        currentState = state
        alive = currentState == .Live
        nextState = currentState
    }
    
    @inlinable
    public final func prepareUpdate() {
        // Lazy helps tremendously as it prevents an intermediate result array from being created
        // For some reason doing this directly is faster than calling the extension:
        liveNeighbors = neighbors.lazy.filter({ $0.alive }).count
        
        if !(currentState == .Dead && liveNeighbors < 3) {
            nextState = (currentState == .Live && liveNeighbors == 2) || (liveNeighbors == 3) ? .Live: .Dead
        }
    }
    
    @inlinable
    public final func update() {
        if needsUpdate() {
            if nextState == .Live {
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
