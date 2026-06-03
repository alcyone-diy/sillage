//
//  CoordinateInputView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-06-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

public enum Hemisphere: String, CaseIterable, Identifiable {
  case north = "N"
  case south = "S"
  case east = "E"
  case west = "W"
  
  public var id: String { rawValue }
}

public enum CoordinateType {
  case latitude
  case longitude
}

struct CoordinateInputView: View {
  let title: String
  let type: CoordinateType
  @Binding var hemisphere: Hemisphere
  @Binding var degrees: Int?
  @Binding var minutes: Double?
  
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .marineFont(.body)
      
      HStack(spacing: 12) {
        // Hemisphere Picker
        Picker("Hemisphere", selection: $hemisphere) {
          if type == .latitude {
            Text("N").tag(Hemisphere.north)
            Text("S").tag(Hemisphere.south)
          } else {
            Text("W").tag(Hemisphere.west)
            Text("E").tag(Hemisphere.east)
          }
        }
        .pickerStyle(.segmented)
        .frame(width: 80)
        
        // Degrees Input
        TextField("Deg", value: $degrees, format: .number)
          .keyboardType(.numberPad)
          .multilineTextAlignment(.trailing)
          .marineFont(.body)
          .frame(maxWidth: 80)
        Text("°")
          .marineFont(.body)
        
        // Minutes Input
        TextField("Min", value: $minutes, format: .number)
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .marineFont(.body)
          .frame(maxWidth: 100)
        Text("'")
          .marineFont(.body)
        
        Spacer(minLength: 0)
      }
    }
    .padding(.vertical, 4)
  }
}
