//
//  Grid.swift
//  MetalGoL
//
//  Created by Albertino Padin on 8/7/22.
//

import Foundation
import MetalKit

final class Grid {
    let xCount: Int
    let yCount: Int
    // TODO: Figure out how to do this in flat array for possibly more performance
    final var grid = ContiguousArray<ContiguousArray<Cell>>()   // 2D Array to hold the cells
    final var backingNodes = ContiguousArray<Node>()
    var generation: UInt64 = 0
    
    final let updateQueue = DispatchQueue(label: "cgol.update.queue",
                                          qos: .userInteractive)
    
    final let aliveColor = SIMD4<Float>(0.0, 1.0, 0.0, 1.0)
    
    init(_ xCells: Int,
         _ yCells: Int,
         device: MTLDevice,
         allocator: MDLMeshBufferAllocator,
         vertexDescriptor: MDLVertexDescriptor) {
        xCount = xCells
        yCount = yCells
        
        // Figure out left and top starting points
        let startX = -Float(xCells/2)
        let startY = -Float(yCells/2)
        for xc in 0..<xCells {
            var column = ContiguousArray<Cell>()
            for yc in 0..<yCells {
                let cell = Cell(device: device,
                                allocator: allocator,
                                vertexDescriptor: vertexDescriptor,
                                color: GREEN_COLOR,
                                position: SIMD3<Float>(startX + Float(xc), startY + Float(yc), 0))
                
                column.append(cell)
                backingNodes.append(cell.node)
            }
            
            grid.append(column)
        }
        
        setNeighborsForAllCellsInGrid()
    }
    
    private func setNeighborsForAllCellsInGrid() {
        for x in 0..<xCount {
            for y in 0..<yCount {
                grid[x][y].neighbors = getCellNeighbors(x: x, y: y)
            }
        }
    }
    
    private func getCellNeighbors(x: Int, y: Int) -> ContiguousArray<Cell> {
        var neighbors = ContiguousArray<Cell>()
        
        // Get the neighbors:
        let leftX   = x - 1
        let rightX  = x + 1
        let topY    = y + 1
        let bottomY = y - 1
        
        let leftNeighbor        = leftX > -1 ? grid[leftX][y] : nil
        let upperLeftNeighbor   = leftX > -1 && topY < yCount ? grid[leftX][topY] : nil
        let upperNeighbor       = topY < yCount ? grid[x][topY] : nil
        let upperRightNeighbor  = rightX < xCount && topY < yCount ? grid[rightX][topY] : nil
        let rightNeighbor       = rightX < xCount ? grid[rightX][y] : nil
        let lowerRightNeighbor  = rightX < xCount && bottomY > -1 ? grid[rightX][bottomY] : nil
        let lowerNeighbor       = bottomY > -1 ? grid[x][bottomY] : nil
        let lowerLeftNeighbor   = leftX > -1 && bottomY > -1 ? grid[leftX][bottomY] : nil
        
        if let left_n = leftNeighbor {
            neighbors.append(left_n)
        }
        
        if let upper_left_n = upperLeftNeighbor {
            neighbors.append(upper_left_n)
        }
        
        if let upper_n = upperNeighbor {
            neighbors.append(upper_n)
        }
        
        if let upper_right_n = upperRightNeighbor {
            neighbors.append(upper_right_n)
        }
        
        if let right_n = rightNeighbor {
            neighbors.append(right_n)
        }
        
        if let lower_right_n = lowerRightNeighbor {
            neighbors.append(lower_right_n)
        }
        
        if let lower_n = lowerNeighbor {
            neighbors.append(lower_n)
        }
        
        if let lower_left_n = lowerLeftNeighbor {
            neighbors.append(lower_left_n)
        }
        
        return neighbors
    }
    
    // Update cells using Conway's Rules of Life:
    // 1) Any live cell with fewer than two live neighbors dies (underpopulation)
    // 2) Any live cell with two or three live neighbors lives on to the next generation
    // 3) Any live cell with more than three live neighbors dies (overpopulation)
    // 4) Any dead cell with exactly three live neighbors becomes a live cell (reproduction)
    // Must apply changes all at once for each generation, so will need copy of current cell grid
    @inlinable
    final func update() -> UInt64 {
        // 2.8 - 3 ms:
        // This also seems to have a similar FPS and Frametime as double concurrentPerform:
        // Prepare update:
        updateQueue.sync {
            DispatchQueue.concurrentPerform(iterations: self.xCount) { x in
                self.grid[x].forEach { $0.prepareUpdate() }
            }
        }

        // Update
        updateQueue.sync {
            DispatchQueue.concurrentPerform(iterations: self.xCount) { x in
                self.grid[x].lazy.filter({ $0.needsUpdate() }).forEach { $0.update() }
            }
        }
        
        generation += 1
        return generation
    }
    
    @inlinable
    final func reset() {
        // Reset the game to initial state with no cells alive:
        updateQueue.sync(flags: .barrier) {
            DispatchQueue.concurrentPerform(iterations: self.xCount) { x in
                DispatchQueue.concurrentPerform(iterations: self.yCount) { y in
                    self.grid[x][y].makeDead()
                }
            }
        }
        
        generation = 0
    }
    
    @inlinable
    final func randomState(liveProbability: Double) {
        reset()
        if liveProbability == 1.0 {
            makeAllLive()
        } else {
            if liveProbability > 0.0 {
                let liveProb = Int(liveProbability*100)
                updateQueue.sync {
                    DispatchQueue.concurrentPerform(iterations: self.xCount) { x in
                        DispatchQueue.concurrentPerform(iterations: self.yCount) { y in
                            let randInt = Int.random(in: 0...100)
                            if randInt <= liveProb {
                                self.grid[x][y].makeLive()
                            }
                        }
                    }
                }
            }
        }
    }
    
    final func makeAllLive() {
        updateQueue.sync {
            DispatchQueue.concurrentPerform(iterations: self.xCount) { x in
                DispatchQueue.concurrentPerform(iterations: self.yCount) { y in
                    self.grid[x][y].makeLive()
                }
            }
        }
    }
}
