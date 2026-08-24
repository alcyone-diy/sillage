//
//  AnchorAlertView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-04.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct AnchorAlertView: View {
  @Environment(AnchorViewModel.self) private var anchorViewModel
  @Environment(\.marineTheme) private var marineTheme
  @Environment(\.locale) private var locale
  
  @State private var isFlashing = false
  
  var body: some View {
    ZStack {
      // Flashing Background
      (isFlashing ? Color(UIColor.systemRed) : Color.black)
        .ignoresSafeArea()
        .animation(
          Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true),
          value: isFlashing
        )
        .onAppear {
          isFlashing = true
        }
      
      VStack(spacing: 40) {
        Spacer()
        
        // Critical Alert Header
        VStack(spacing: 16) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 64, weight: .heavy))
            .foregroundColor(.white)
          
          Text("DRAGGING ANCHOR")
            .font(.system(size: 32, weight: .black, design: .default))
            .foregroundColor(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 16)
            .multilineTextAlignment(.center)

          if let reasonDesc = anchorViewModel.triggerReasonDescription {
            Text(reasonDesc)
              .font(.system(size: 18, weight: .bold))
              .foregroundColor(.white)
              .padding(.horizontal, 16)
              .padding(.vertical, 8)
              .background(Color.black.opacity(0.4))
              .cornerRadius(12)
              .multilineTextAlignment(.center)
          }
        }
        
        // Telemetry Data
        VStack(spacing: 24) {
          HStack(spacing: 0) {
            Spacer()
            
            // Speed (SOG)
            VStack(spacing: 8) {
              Text("SOG")
                .marineFont(.instrumentLabel)
                .foregroundColor(.white.opacity(0.8))
              
              if let sog = anchorViewModel.sog {
                Text(sog.marineFormatted)
                  .font(.system(size: 32, weight: .bold, design: .monospaced))
                  .lineLimit(1)
                  .minimumScaleFactor(0.6)
                  .foregroundColor(.white)
              } else {
                Text("--")
                  .font(.system(size: 32, weight: .bold, design: .monospaced))
                  .lineLimit(1)
                  .foregroundColor(.white)
              }
            }
            
            Spacer()
            
            // Distance
            VStack(spacing: 8) {
              Text("DISTANCE")
                .marineFont(.instrumentLabel)
                .foregroundColor(.white.opacity(0.8))
              
              if let dist = anchorViewModel.currentDistance {
                Text(dist.marineAnchorDistanceFormatted(locale: locale))
                  .font(.system(size: 32, weight: .bold, design: .monospaced))
                  .lineLimit(1)
                  .minimumScaleFactor(0.6)
                  .foregroundColor(.white)
              } else {
                Text("--")
                  .font(.system(size: 32, weight: .bold, design: .monospaced))
                  .lineLimit(1)
                  .foregroundColor(.white)
              }
            }
            
            Spacer()
            
            // Limit
            VStack(spacing: 8) {
              Text("LIMIT")
                .marineFont(.instrumentLabel)
                .foregroundColor(.white.opacity(0.8))
              
              Text(anchorViewModel.configuredRadius.marineAnchorDistanceFormatted(locale: locale))
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundColor(.white)
            }
            
            Spacer()
          }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(Color.black.opacity(0.5))
        .cornerRadius(20)

        
        Spacer()
        
        // Action Buttons
        VStack(spacing: 16) {
          Button(action: {
            anchorViewModel.silenceAlert()
          }) {
            Text(anchorViewModel.isAlertSilenced ? "ALERT SILENCED" : "SILENCE ALERT")
              .font(.system(size: 28, weight: .bold))
              .foregroundColor(anchorViewModel.isAlertSilenced ? .gray : .white)
              .frame(maxWidth: .infinity)
              .frame(height: max(80, marineTheme.minTouchTarget))
              .background(anchorViewModel.isAlertSilenced ? Color.black.opacity(0.5) : Color(UIColor.systemRed))
              .cornerRadius(16)
              .overlay(
                RoundedRectangle(cornerRadius: 16)
                  .stroke(Color.white.opacity(0.5), lineWidth: 2)
              )
          }
          .disabled(anchorViewModel.isAlertSilenced)
          
          Button(action: {
            anchorViewModel.disarmAlarm()
          }) {
            Text("DISARM ANCHOR")
              .font(.system(size: 24, weight: .bold))
              .foregroundColor(Color(UIColor.systemRed))
              .frame(maxWidth: .infinity)
              .frame(height: max(60, marineTheme.minTouchTarget))
              .background(Color.black.opacity(0.7))
              .cornerRadius(16)
              .overlay(
                RoundedRectangle(cornerRadius: 16)
                  .stroke(Color(UIColor.systemRed).opacity(0.8), lineWidth: 2)
              )
          }
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 60)
      }
    }
  }
}
