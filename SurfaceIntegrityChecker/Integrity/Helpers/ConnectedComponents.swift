//
//  ConnectedComponents.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 9/1/25.
//

import Foundation
import ARKit
import RealityFoundation

struct MeshTopology {
    let faceCount: Int
    let neighbors: [[Int]]   // adjacency by shared edge
    let areas: [Float]       // per-face triangle area (m^2)
}

private struct EdgeKey: Hashable {
    let part: Int
    let a: UInt32
    let b: UInt32
    init(part: Int, _ i: UInt32, _ j: UInt32) {
        self.part = part
        if i <= j { self.a = i; self.b = j } else { self.a = j; self.b = i }
    }
}

struct Component {
    let faceIndices: [Int]
    let totalArea: Float
}

class ConnectedComponents {
    func buildTopology(_ mesh: MeshResource) -> MeshTopology {
        var neighbors: [[Int]] = []
        var areas: [Float] = []
        neighbors.reserveCapacity(1024)
        areas.reserveCapacity(1024)
        
        // Get the triangles from the mesh
        var edgeMap: [EdgeKey: [Int]] = [:]
        var globalFaceBase = 0
        
        let models = mesh.contents.models
        for (mIdx, model) in models.enumerated() {
            for (pIdx, part) in model.parts.enumerated() {
                let positions: [SIMD3<Float>] = part.positions.elements
                let triIdx: [UInt32]
                if let idx = part.triangleIndices?.elements {
                    triIdx = idx
                } else {
                    // Non-indexed triangles: assume positions come in groups of 3
                    print("Non-indexed triangles found")
                    print("Positions count: \(positions.count), Triangles count: \(positions.count / 3)")
                    triIdx = Array(0..<UInt32(positions.count))
                }
                
                let triCount = triIdx.count / 3
                neighbors.append(contentsOf: Array(repeating: [], count: triCount))
                areas.append(contentsOf: Array(repeating: 0, count: triCount))
                
                for t in 0..<triCount {
                    let gFace = globalFaceBase + t
                    
                    let i0 = triIdx[3*t + 0]
                    let i1 = triIdx[3*t + 1]
                    let i2 = triIdx[3*t + 2]
                    
                    // Store area for thresholding later
                    let p0 = positions[Int(i0)]
                    let p1 = positions[Int(i1)]
                    let p2 = positions[Int(i2)]
                    let e1 = p1 - p0, e2 = p2 - p0
                    areas[gFace] = 0.5 * simd_length(simd_cross(e1, e2))
                    
                    // Build undirected edges for this triangle within this part
                    let e01 = EdgeKey(part: pIdx | (mIdx << 16), i0, i1)
                    let e12 = EdgeKey(part: pIdx | (mIdx << 16), i1, i2)
                    let e20 = EdgeKey(part: pIdx | (mIdx << 16), i2, i0)
                    
                    edgeMap[e01, default: []].append(gFace)
                    edgeMap[e12, default: []].append(gFace)
                    edgeMap[e20, default: []].append(gFace)
                }
                globalFaceBase += triCount
            }
        }
        
        // Convert edge → [faces] into per-face neighbors (only edges shared by 2 faces)
        for (_, facesOnEdge) in edgeMap {
            if facesOnEdge.count == 2 {
                let a = facesOnEdge[0], b = facesOnEdge[1]
                neighbors[a].append(b)
                neighbors[b].append(a)
            }
            // edges with count == 1 are boundary edges; we ignore them for adjacency
        }
        
        return MeshTopology(faceCount: neighbors.count, neighbors: neighbors, areas: areas)
    }
    
    /**
    This function identifies connected components in a 3D mesh.
     Basic version that performs a depth-first search (DFS) to find connected components.
     */
    func getConnectedComponents(
        _ mesh: MeshResource,
        kKeep: Int = 2, // Keep face only if more than kKeep faces in component
        kDilate: Int = 0, // Dilate component if more than kDilate neighbors in component
        minFaces: Int = 6, // Minimum faces to keep component
        minArea: Float = 0.001 // Minimum total area (m^2) to keep component)
    ) -> [Component] {
        let topology = buildTopology(mesh)
        
        var dev = Array(repeating: true, count: topology.faceCount)
        
        if kKeep > 0 {
            var kept = dev
            for i in 0..<topology.faceCount where dev[i] {
                var cnt = 0
                for j in topology.neighbors[i] where dev[j] { cnt += 1 }
                if cnt < kKeep { kept[i] = false }
            }
            dev = kept
        }
        
        if kDilate > 0 {
            // Create a copy of dev
            var dil = dev
            for i in 0..<topology.faceCount where !dev[i] {
                var cnt = 0
                for j in topology.neighbors[i] where dev[j] { cnt += 1 }
                if cnt >= kDilate { dil[i] = true }
            }
            dev = dil
        }
        
        // ---- DFS over all dev faces ----
        var visited = [Bool](repeating: false, count: topology.faceCount)
        var components: [Component] = []
        
        for s in 0..<topology.faceCount where dev[s] && !visited[s] {
            // Found a new component; DFS from here
            var stack = [s]
            visited[s] = true
            var faces: [Int] = []
            var area: Float = 0
            
            while let i = stack.popLast() {
                faces.append(i)
                area += topology.areas[i]
                for j in topology.neighbors[i] where dev[j] && !visited[j] {
                    visited[j] = true
                    stack.append(j)
                }
            }
            
            if faces.count >= minFaces && area >= minArea {
                components.append(Component(faceIndices: faces, totalArea: area))
            }
        }
        
        return components
    }
}
