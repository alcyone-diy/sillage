//
//  VesselGraphicsFactory.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import UIKit

class VesselGraphicsFactory {

  /// Draws a sleek isosceles triangle pointing upwards and returns it as a UIImage.
  /// The center of the generated image matches the vessel's pivot point.
  static func createVesselImage(size: CGSize = CGSize(width: 24, height: 36), color: UIColor = .systemBlue) -> UIImage? {
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    guard let context = UIGraphicsGetCurrentContext() else {
      return nil
    }

    // Draw an isosceles triangle
    // A simple triangle (0, h) to (w/2, 0) to (w, h) has its centroid at y = 2/3 * h.
    // To make the centroid of the drawn shape exactly at the canvas center (w/2, h/2),
    // we should offset the drawing so the centroid lands exactly on (w/2, h/2).
    // Let's define the triangle points relative to a centroid at (0,0), then shift by (w/2, h/2).

    // We want a shape pointing upwards.
    // Let's use a standard cursor shape: an isosceles triangle with a V-cut at the bottom.
    // Coordinates relative to centroid (0,0):
    // Top: (0, -h/2)
    // Bottom left: (-w/2, h/2)
    // Bottom right: (w/2, h/2)
    // Bottom center cut: (0, h/4)

    // The centroid of a polygon can be calculated, but since we are generating an image,
    // we just need the "pivot point" (which the user wants to be the center of the image)
    // to match the visual center of mass.
    // Let's make the bounding box of the visual shape perfectly centered.
    let shapeHeight = size.height * 0.8
    let shapeWidth = size.width * 0.8

    let centerX = size.width / 2
    let centerY = size.height / 2

    // Offset the Y coordinates so the shape looks balanced around the center.
    // An isosceles triangle with height H has its centroid at H/3 from the base.
    // So the top point is 2/3 H above the centroid, and the base is 1/3 H below.
    let topY = centerY - (shapeHeight * 2.0 / 3.0)
    let bottomY = centerY + (shapeHeight * 1.0 / 3.0)

    let topPoint = CGPoint(x: centerX, y: topY)
    let bottomLeft = CGPoint(x: centerX - shapeWidth / 2, y: bottomY)
    let bottomRight = CGPoint(x: centerX + shapeWidth / 2, y: bottomY)

    // Let's make the bottom cut slightly indent towards the centroid.
    let bottomCenter = CGPoint(x: centerX, y: centerY + (shapeHeight * 0.1))

    let path = UIBezierPath()
    path.move(to: topPoint)
    path.addLine(to: bottomRight)
    path.addLine(to: bottomCenter)
    path.addLine(to: bottomLeft)
    path.close()

    color.setFill()
    path.fill()

    // Add a slight border for visibility
    UIColor.white.setStroke()
    path.lineWidth = 1.5
    path.stroke()

    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    return image
  }
}
