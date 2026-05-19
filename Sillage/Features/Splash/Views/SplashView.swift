//
//  SplashView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-20.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct SplashView: View {
  let state: AppState
  let retryAction: () -> Void
  
  init(state: AppState, retryAction: @escaping () -> Void) {
    self.state = state
    self.retryAction = retryAction
  }
  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      
      VStack(spacing: 32) {
        Text("ALCYONE SILLAGE")
          .marineFont(.largeTitle)
          .foregroundColor(.accentColor)
        
        switch state {
        case .uninitialized, .bootstrapping:
          VStack(spacing: 16) {
            ProgressView()
              .controlSize(.large)
              .tint(.accentColor)
            
            Text("Initializing Systems...")
              .marineFont(.body)
              .foregroundColor(.secondary)
          }
          
        case .error(let error):
          VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.system(size: 40))
              .foregroundColor(.red)
            
            Text("Initialization Failed")
              .marineFont(.headline)
              .foregroundColor(.red)
            
            Text(error.localizedDescription)
              .marineFont(.body)
              .foregroundColor(.white)
              .multilineTextAlignment(.center)
              .padding(.horizontal)
            
            Button(action: retryAction) {
              Text("Retry")
            }
            .buttonStyle(MarineButtonStyle())
          }
          
        case .ready:
          EmptyView()
        }
      }
    }
  }
}
