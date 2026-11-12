//
//  WorldMagneticModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-12.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Pure Swift implementation of the World Magnetic Model (WMM) spherical harmonic synthesis.
///
/// Implements the official NOAA / NCEI WMM algorithms (up to spherical harmonic degree 12),
/// including geodetic to spherical coordinate conversion (WGS-84), Schmidt semi-normalized
/// associated Legendre polynomials via recurrence relations, spherical harmonic summation,
/// and rotation back into local geodetic tangent coordinates (North, East, Down).
nonisolated public struct WorldMagneticModel: Sendable {

  public let epoch: Double
  public let modelName: String
  public let releaseDate: String

  public static let maxDegree: Int = 12

  // Flat arrays for spherical harmonic coefficients up to degree 12.
  // Index formula: n * (n + 1) / 2 + m
  private let g: [Double]
  private let h: [Double]
  private let dg: [Double]
  private let dh: [Double]

  public enum ParseError: Error, Sendable {
    case emptyFile
    case invalidHeader
  }

  public init(
    epoch: Double,
    modelName: String,
    releaseDate: String,
    g: [Double],
    h: [Double],
    dg: [Double],
    dh: [Double]
  ) {
    self.epoch = epoch
    self.modelName = modelName
    self.releaseDate = releaseDate
    self.g = g
    self.h = h
    self.dg = dg
    self.dh = dh
  }

  /// Parses a NOAA formatted `WMM.COF` file content.
  public static func parse(content: String) throws -> WorldMagneticModel {
    let lines = content.components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }

    guard let header = lines.first else {
      throw ParseError.emptyFile
    }

    let headerTokens = header.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard headerTokens.count >= 2, let epoch = Double(headerTokens[0]) else {
      throw ParseError.invalidHeader
    }
    let modelName = headerTokens[1]
    let releaseDate = headerTokens.count >= 3 ? headerTokens[2] : ""

    let totalEntries = (maxDegree + 1) * (maxDegree + 2) / 2
    var g = [Double](repeating: 0.0, count: totalEntries)
    var h = [Double](repeating: 0.0, count: totalEntries)
    var dg = [Double](repeating: 0.0, count: totalEntries)
    var dh = [Double](repeating: 0.0, count: totalEntries)

    for line in lines.dropFirst() {
      if line.hasPrefix("9999") {
        break
      }
      let tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
      guard tokens.count >= 6,
            let n = Int(tokens[0]),
            let m = Int(tokens[1]),
            let gVal = Double(tokens[2]),
            let hVal = Double(tokens[3]),
            let dgVal = Double(tokens[4]),
            let dhVal = Double(tokens[5]) else {
        continue
      }

      guard n >= 1, n <= maxDegree, m >= 0, m <= n else {
        continue
      }

      let idx = n * (n + 1) / 2 + m
      if idx < totalEntries {
        g[idx] = gVal
        h[idx] = hVal
        dg[idx] = dgVal
        dh[idx] = dhVal
      }
    }

    return WorldMagneticModel(
      epoch: epoch,
      modelName: modelName,
      releaseDate: releaseDate,
      g: g,
      h: h,
      dg: dg,
      dh: dh
    )
  }

  /// Calculates magnetic declination in decimal degrees (-180.0 to +180.0, positive East, negative West).
  ///
  /// - Parameters:
  ///   - latitudeDegrees: Geodetic latitude (-90.0 to +90.0 degrees).
  ///   - longitudeDegrees: Geodetic longitude (-180.0 to +180.0 degrees).
  ///   - altitudeMeters: Altitude in meters above the WGS-84 reference ellipsoid (defaults to 0.0).
  ///   - decimalYear: Target epoch year (e.g., 2026.0).
  /// - Returns: Magnetic declination in degrees, or `nil` if coordinates are invalid.
  public func calculateDeclination(
    latitudeDegrees: Double,
    longitudeDegrees: Double,
    altitudeMeters: Double = 0.0,
    decimalYear: Double
  ) -> Double? {
    guard latitudeDegrees >= -90.0 && latitudeDegrees <= 90.0 else { return nil }
    guard longitudeDegrees >= -180.0 && longitudeDegrees <= 180.0 else { return nil }

    // WGS-84 ellipsoid parameters (matching NOAA MAG_SetDefaults)
    let a = 6378.137 // semi-major axis (km)
    let fla = 1.0 / 298.257223563 // flattening
    let epssq = fla * (2.0 - fla) // first eccentricity squared
    let re = 6371.2 // geomagnetic mean radius of Earth (km)

    let phiRad = latitudeDegrees * .pi / 180.0
    let cosLat = cos(phiRad)
    let sinLat = sin(phiRad)
    let altKm = altitudeMeters / 1000.0

    // Geodetic to Spherical conversion
    let rc = a / sqrt(1.0 - epssq * sinLat * sinLat)
    let xp = (rc + altKm) * cosLat
    let zp = (rc * (1.0 - epssq) + altKm) * sinLat
    let r = sqrt(xp * xp + zp * zp)
    guard r > 0 else { return nil }

    let sinPhig = zp / r
    let phigRad = asin(max(-1.0, min(1.0, sinPhig)))
    let phigDeg = phigRad * 180.0 / .pi

    // Time difference from epoch
    let dt = decimalYear - epoch

    // Compute Legendre polynomials (Pcup and dPcup) via NOAA MAG_PcupLow
    let (pcup, dpcup) = computeLegendre(sinLatitude: sinPhig)

    // Compute relative radius powers: (re / r)^(n + 2)
    var relRadiusPower = [Double](repeating: 0.0, count: Self.maxDegree + 1)
    let ratio = re / r
    relRadiusPower[0] = ratio * ratio
    for n in 1...Self.maxDegree {
      relRadiusPower[n] = relRadiusPower[n - 1] * ratio
    }

    // Longitude in radians
    let lonRad = longitudeDegrees * .pi / 180.0

    // Spherical harmonics summation (NOAA MAG_Summation)
    var bxSph = 0.0
    var bySph = 0.0
    var bzSph = 0.0

    for n in 1...Self.maxDegree {
      for m in 0...n {
        let index = n * (n + 1) / 2 + m
        let gnm = g[index] + dt * dg[index]
        let hnm = h[index] + dt * dh[index]
        let cosMLon = cos(Double(m) * lonRad)
        let sinMLon = sin(Double(m) * lonRad)

        // Radial component Bz (Down in spherical coords)
        bzSph -= relRadiusPower[n] * (gnm * cosMLon + hnm * sinMLon) * Double(n + 1) * pcup[index]

        // Longitudinal component By (East in spherical coords before 1/cos(phi))
        bySph += relRadiusPower[n] * (gnm * sinMLon - hnm * cosMLon) * Double(m) * pcup[index]

        // Latitudinal component Bx (North in spherical coords)
        bxSph -= relRadiusPower[n] * (gnm * cosMLon + hnm * sinMLon) * dpcup[index]
      }
    }

    let cosPhig = cos(phigRad)
    if abs(cosPhig) > 1e-10 {
      bySph /= cosPhig
    }

    // Rotate spherical field components to local geodetic system (NOAA MAG_RotateMagneticVector)
    let psi = (phigDeg - latitudeDegrees) * .pi / 180.0
    let bx = bxSph * cos(psi) - bzSph * sin(psi) // North
    let by = bySph                                // East

    let declinationRadians = atan2(by, bx)
    return declinationRadians * 180.0 / .pi
  }

  // MARK: - Legendre Polynomials (NOAA MAG_PcupLow algorithm)

  private func computeLegendre(sinLatitude x: Double) -> (p: [Double], dp: [Double]) {
    let numTerms = (Self.maxDegree + 1) * (Self.maxDegree + 2) / 2
    var pcup = [Double](repeating: 0.0, count: numTerms)
    var dpcup = [Double](repeating: 0.0, count: numTerms)
    var schmidt = [Double](repeating: 0.0, count: numTerms)

    pcup[0] = 1.0
    dpcup[0] = 0.0
    let z = sqrt(max(0.0, (1.0 - x) * (1.0 + x)))

    // Gauss-normalized associated Legendre functions recurrence
    for n in 1...Self.maxDegree {
      for m in 0...n {
        let index = n * (n + 1) / 2 + m
        if n == m {
          let idxPrev = (n - 1) * n / 2 + m - 1
          pcup[index] = z * pcup[idxPrev]
          dpcup[index] = z * dpcup[idxPrev] + x * pcup[idxPrev]
        } else if n == 1 && m == 0 {
          let idxPrev = (n - 1) * n / 2 + m
          pcup[index] = x * pcup[idxPrev]
          dpcup[index] = x * dpcup[idxPrev] - z * pcup[idxPrev]
        } else if n > 1 && n != m {
          let idx1 = (n - 2) * (n - 1) / 2 + m
          let idx2 = (n - 1) * n / 2 + m
          if m > n - 2 {
            pcup[index] = x * pcup[idx2]
            dpcup[index] = x * dpcup[idx2] - z * pcup[idx2]
          } else {
            let k = Double((n - 1) * (n - 1) - m * m) / Double((2 * n - 1) * (2 * n - 3))
            pcup[index] = x * pcup[idx2] - k * pcup[idx1]
            dpcup[index] = x * dpcup[idx2] - z * pcup[idx2] - k * dpcup[idx1]
          }
        }
      }
    }

    // Schmidt quasi-normalization ratios
    schmidt[0] = 1.0
    for n in 1...Self.maxDegree {
      let index = n * (n + 1) / 2
      let idxPrev = (n - 1) * n / 2
      schmidt[index] = schmidt[idxPrev] * Double(2 * n - 1) / Double(n)
      for m in 1...n {
        let i = n * (n + 1) / 2 + m
        let iPrev = n * (n + 1) / 2 + m - 1
        schmidt[i] = schmidt[iPrev] * sqrt(Double((n - m + 1) * (m == 1 ? 2 : 1)) / Double(n + m))
      }
    }

    // Convert Gauss-normalized functions to Schmidt quasi-normalized version
    for n in 1...Self.maxDegree {
      for m in 0...n {
        let index = n * (n + 1) / 2 + m
        pcup[index] = pcup[index] * schmidt[index]
        dpcup[index] = -dpcup[index] * schmidt[index]
      }
    }

    return (pcup, dpcup)
  }
}
