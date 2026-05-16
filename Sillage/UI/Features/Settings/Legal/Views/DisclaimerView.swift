//
//  DisclaimerView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct DisclaimerView: View {
  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(spacing: 30) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 60))
            .foregroundColor(.yellow)
            .padding(.top, 40)

          Text("Maritime Navigation Warning")
            .font(.largeTitle.bold())
            .multilineTextAlignment(.center)
            .foregroundColor(.primary)

          Text(Constants.maritimeNavigationWarning)
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
          PreferencesService.shared.hasAcceptedDisclaimer = true
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

#Preview {
  DisclaimerView()
}
