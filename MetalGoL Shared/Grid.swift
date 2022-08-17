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
    let totalCount: Int
    final var cells = ContiguousArray<Cell>()
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
        totalCount = xCells * yCells
        
        // Figure out left and top starting points
        let startX = -Float(xCells/2)
        let startY = -Float(yCells/2)
        for xc in 0..<xCells {
            for yc in 0..<yCells {
                let cell = Cell(device: device,
                                allocator: allocator,
                                vertexDescriptor: vertexDescriptor,
                                color: GREEN_COLOR,
                                position: SIMD3<Float>(startX + Float(xc), startY + Float(yc), 0))
                
                cells.append(cell)
            }
        }
        
        setNeighborsForAllCellsInGrid()
    }
    
    private func setNeighborsForAllCellsInGrid() {
        for x in 0..<xCount {
            for y in 0..<yCount {
                cells[x + y*xCount].neighbors = getCellNeighbors(x: x, y: y)
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
        
        let leftNeighbor        = leftX > -1 ? cells[leftX + y*xCount] : nil
        let upperLeftNeighbor   = leftX > -1 && topY < yCount ? cells[leftX + topY*xCount] : nil
        let upperNeighbor       = topY < yCount ? cells[x + topY*xCount] : nil
        let upperRightNeighbor  = rightX < xCount && topY < yCount ? cells[rightX + topY*xCount] : nil
        let rightNeighbor       = rightX < xCount ? cells[rightX + y*xCount] : nil
        let lowerRightNeighbor  = rightX < xCount && bottomY > -1 ? cells[rightX + bottomY*xCount] : nil
        let lowerNeighbor       = bottomY > -1 ? cells[x + bottomY*xCount] : nil
        let lowerLeftNeighbor   = leftX > -1 && bottomY > -1 ? cells[leftX + bottomY*xCount] : nil
        
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
        updateQueue.sync {
            DispatchQueue.concurrentPerform(iterations: self.xCount) { x in
                DispatchQueue.concurrentPerform(iterations: self.yCount) { y in
                    self.cells[x + y*xCount].prepareUpdate()
                }
            }
        }

        updateQueue.sync {
            DispatchQueue.concurrentPerform(iterations: self.xCount) { x in
                DispatchQueue.concurrentPerform(iterations: self.yCount) { y in
                    self.cells[x + y*xCount].update()
                }
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
                    self.cells[x + y*xCount].makeDead()
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
                                self.cells[x + y*xCount].makeLive()
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
                    self.cells[x + y*xCount].makeLive()
                }
            }
        }
    }
}
