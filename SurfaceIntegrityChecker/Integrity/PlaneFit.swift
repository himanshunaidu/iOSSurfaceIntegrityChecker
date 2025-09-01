//
//  PlaneFit.swift
//  SurfaceIntegrityChecker
//
//  Created by Himanshu on 9/1/25.
//

import simd
import Accelerate

struct Plane {
    var n: simd_float3 // Normal vector
    var d: Float      // Offset from origin
}

class PlaneFit {    
    /**
     Fit a plane to a set of 3D points using PCA.
     This algorithm is used for fitting a plane for a polygon mesh.
     It uses the centroids of the polygons, weighted by their areas.
     */
    static func fitPlanePCA(_ points: [simd_float3], weights: [Float]) -> Plane? {
        guard points.count>=3, points.count==weights.count else {
            return nil
        }
        // Compute weighted centroid
        let W = weights.reduce(0, +)
        var mu = simd_float3(0, 0, 0)
        for (p, w) in zip(points, weights) {
            mu += w * p
        }
        mu = mu / max(W, 1e-6)
        
        // Compute covariance matrix
        var cov = simd_float3x3(0)
        for (p, w) in zip(points, weights) {
            let diff = p - mu
            cov += w * simd_float3x3(rows: [
                simd_float3(diff.x * diff.x, diff.x * diff.y, diff.x * diff.z),
                simd_float3(diff.y * diff.x, diff.y * diff.y, diff.y * diff.z),
                simd_float3(diff.z * diff.x, diff.z * diff.y, diff.z * diff.z)
            ])
        }
        cov = simd_float3x3(rows: [
            cov[0] / max(W, 1e-6),
            cov[1] / max(W, 1e-6),
            cov[2] / max(W, 1e-6)
        ])
        
        var a = [
            cov[0][0], cov[0][1], cov[0][2],
            cov[1][0], cov[1][1], cov[1][2],
            cov[2][0], cov[2][1], cov[2][2]
        ]
        var w = [Float](repeating: 0, count: 3)
        var jobz: Character = "V" /* 'V' */, uplo: Character = "U" /* 'U' */
        var n = Int32(3), lda = Int32(3), info = Int32(0)
        var lwork: Int32 = 8
        var work = [Float](repeating: 0, count: Int(lwork))
        ssyev_(&jobz, &uplo, &n, &a, &lda, &w, &work, &lwork, &info)
        
        guard info == 0 else {
            return nil
        }
        let normal = simd_normalize(simd_float3(a[0], a[1], a[2]))
        let d = -simd_dot(normal, mu)
        
        return Plane(n: normal, d: d)
    }
}
