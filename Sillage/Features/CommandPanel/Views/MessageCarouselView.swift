//
//  MessageCarouselView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-19.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

struct CardHeightPreferenceKey: PreferenceKey {
  static var defaultValue: [UUID: CGFloat] = [:]
  static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
    value.merge(nextValue(), uniquingKeysWith: { $1 })
  }
}

private struct ScrollInfo: Equatable {
  var offset: CGFloat = 0
  var width: CGFloat = 1
}

@MainActor
struct MessageCarouselView: View {
  @Environment(MessageService.self) private var messageService
  @Environment(\.marineTheme) private var marineTheme

  @State private var scrolledID: UUID?
  @State private var cardHeights: [UUID: CGFloat] = [:]
  @State private var scrollInfo = ScrollInfo()
  @State private var animatedTargetHeight: CGFloat? = nil

  private var targetScrollHeight: CGFloat? {
    let count = messageService.messages.count
    guard count > 0 else { return nil }
    
    let offset = scrollInfo.offset
    let width = scrollInfo.width
    
    // Handle rubber banding by clamping offset
    let clampedOffset = max(0, min(offset, CGFloat(count - 1) * width))
    
    let firstIndex = max(0, Int(clampedOffset / width))
    let lastIndex = min(count - 1, Int((clampedOffset + width - 0.1) / width))
    
    var maxHeight: CGFloat = 0
    for i in firstIndex...lastIndex {
      let id = messageService.messages[i].id
      if let height = cardHeights[id] {
        maxHeight = max(maxHeight, height)
      }
    }
    
    // Add 10 points to accommodate the bottom shadow (radius 4 + y-offset 2)
    return maxHeight > 0 ? maxHeight + 10 : nil
  }

  var body: some View {
    if !messageService.messages.isEmpty {
      VStack(spacing: MarineTheme.Spacing.small) {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(alignment: .top, spacing: 0) {
            ForEach(messageService.messages) { message in
              MessageCardView(message: message)
                .padding(.horizontal, MarineTheme.Spacing.medium)
                .containerRelativeFrame(.horizontal, alignment: .top)
                .id(message.id)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
          }
          .animation(.spring(response: 0.4, dampingFraction: 0.8), value: messageService.messages)
          .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledID)
        .scrollClipDisabled()
        .onPreferenceChange(CardHeightPreferenceKey.self) { newHeights in
          cardHeights = newHeights
        }
        .onScrollGeometryChange(for: ScrollInfo.self) { geo in
          ScrollInfo(offset: geo.contentOffset.x, width: max(1, geo.containerSize.width))
        } action: { _, newValue in
          scrollInfo = newValue
        }
        .frame(height: animatedTargetHeight ?? targetScrollHeight, alignment: .top)
        .onChange(of: targetScrollHeight) { _, newValue in
          withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            animatedTargetHeight = newValue
          }
        }
        
        // Pagination dots
        if messageService.messages.count > 1 {
          HStack(spacing: 6) {
            ForEach(messageService.messages) { message in
              Circle()
                .fill(message.id == scrolledID ? MarineTheme.Colors.primary : Color.secondary.opacity(0.3))
                .frame(width: 6, height: 6)
            }
          }
          .offset(y: -8)
        }
      }
      .onAppear {
        if scrolledID == nil {
          scrolledID = messageService.messages.first?.id
        }
      }
    }
  }
}

@MainActor
struct MessageCardView: View {
  let message: AppMessage
  @Environment(MessageService.self) private var messageService
  @Environment(\.marineTheme) private var marineTheme

  var body: some View {
    VStack(alignment: .leading, spacing: MarineTheme.Spacing.small) {
      HStack(alignment: .top) {
        severityIcon
        
        VStack(alignment: .leading, spacing: 2) {
          Text(message.title)
            .marineFont(.headline)
            .foregroundStyle(.primary)
            .lineLimit(1)
            
          Text(message.detail)
            .marineFont(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.trailing, 24) // Reserve space for the close button
        
        Spacer(minLength: 0)
      }
    }
    .padding(MarineTheme.Spacing.medium)
    .background(Color(uiColor: .secondarySystemGroupedBackground))
    .cornerRadius(12)
    .overlay(alignment: .topTrailing) {
      if message.isDismissable {
        Button {
          withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            messageService.removeMessage(id: message.id)
          }
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(marineTheme.isGloveMode ? .title : .title3)
            .foregroundStyle(.tertiary)
            .frame(width: marineTheme.minTouchTarget, height: marineTheme.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .alignmentGuide(.trailing) { d in
          // Keep the visual center invariant (e.g. 18 points from the right edge)
          d.width / 2 + 18
        }
        .alignmentGuide(.top) { d in
          // Keep the visual center invariant (e.g. 18 points from the top edge)
          d.height / 2 - 18
        }
      }
    }
    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    .background(
      GeometryReader { geo in
        Color.clear.preference(
          key: CardHeightPreferenceKey.self,
          value: [message.id: geo.size.height]
        )
      }
    )
    .animation(nil, value: marineTheme.isGloveMode)
  }
  
  @ViewBuilder
  private var severityIcon: some View {
    switch message.severity {
    case .info:
      Image(systemName: "info.circle.fill")
        .foregroundStyle(.blue)
        .font(.title2)
    case .warning:
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
        .font(.title2)
    case .error:
      Image(systemName: "xmark.octagon.fill")
        .foregroundStyle(.red)
        .font(.title2)
    }
  }
}
