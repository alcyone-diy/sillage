//
//  DisclaimerView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct DisclaimerView: View {
  @Environment(PreferencesService.self) private var preferencesService
  private let maritimeNavigationWarning: LocalizedStringResource = "WARNING: Alcyone Sillage is an electronic navigational aid designed for situational awareness only. It must not be used as the primary means of navigation. This application does not replace official government charts, official notices to mariners, or prudent seamanship. The captain of the vessel assumes all responsibility and liability for the safety of the ship and its crew. Never rely on a single source of information and always maintain a proper visual lookout."

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(spacing: 30) {
          Image(marineIcon: .warningFill)
            .font(.system(size: 60))
            .foregroundColor(.yellow)
            .padding(.top, 40)

          Text("Maritime Navigation Warning")
            .font(.largeTitle.bold())
            .multilineTextAlignment(.center)
            .foregroundColor(.primary)

          Text(maritimeNavigationWarning)
            .font(.body)
            .fontWeight(.medium)
            .multilineTextAlignment(.leading)
            .foregroundColor(.primary)
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
        }
        .padding()
      }

      Spacer(minLength: 0)

      // Bottom Action Area
      VStack {
        Button(action: {
          preferencesService.hasAcceptedDisclaimer = true
        }) {
          Text("I Accept")
            .font(.title2.bold())
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 60)
            .background(Color.blue)
            .cornerRadius(12)
        }
        .padding()
      }
      .background(Color(uiColor: .systemBackground))
      .shadow(color: Color.black.opacity(0.1), radius: 5, y: -5)
    }
  }
}
