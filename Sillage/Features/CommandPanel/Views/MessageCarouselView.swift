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
  var width: CGFloat?
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
    guard let width = scrollInfo.width, width > 0 else { return nil }
    
    let offset = scrollInfo.offset
    
    // Handle rubber banding by clamping offset
    let clampedOffset = max(0, min(offset, CGFloat(count - 1) * width))
    
    let firstIndex = max(0, Int(floor(clampedOffset / width)))
    let lastIndex = min(count - 1, Int(ceil(clampedOffset / width)))
    
    var maxHeight: CGFloat = 0
    for i in firstIndex...lastIndex {
      let id = messageService.messages[i].id
      if let height = cardHeights[id] {
        maxHeight = max(maxHeight, height)
      }
    }
    
    // Add the space required for the shadow padding
    return maxHeight > 0 ? maxHeight + MarineTheme.Metrics.shadowRadius + MarineTheme.Metrics.shadowOffset : nil
  }

  var body: some View {
    if !messageService.messages.isEmpty {
      VStack(spacing: MarineTheme.Spacing.small) {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(alignment: .top, spacing: 0) {
            ForEach(messageService.messages) { message in
              MessageCardView(message: message)
                .padding(.bottom, MarineTheme.Metrics.shadowRadius + MarineTheme.Metrics.shadowOffset) // Structural padding for shadow
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
          ScrollInfo(offset: geo.contentOffset.x, width: geo.containerSize.width > 0 ? geo.containerSize.width : nil)
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
          HStack(spacing: MarineTheme.Spacing.small) {
            ForEach(messageService.messages) { message in
              Circle()
                .fill(message.id == scrolledID ? MarineTheme.Colors.primary : Color.secondary.opacity(0.3))
                .frame(width: MarineTheme.Metrics.paginationDotSize, height: MarineTheme.Metrics.paginationDotSize)
            }
          }
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
        
        VStack(alignment: .leading, spacing: MarineTheme.Spacing.tiny) {
          Text(message.title)
            .marineFont(.headline)
            .foregroundStyle(.primary)
            .lineLimit(1)
            
          Text(message.detail)
            .marineFont(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.trailing, MarineTheme.Spacing.extraLarge) // Reserve space for the close button
        
        Spacer(minLength: 0)
      }
    }
    .padding(MarineTheme.Spacing.medium)
    .background(Color(uiColor: .secondarySystemGroupedBackground))
    .cornerRadius(MarineTheme.Metrics.cornerRadius)
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
          // Keep the visual center invariant
          d.width / 2 + MarineTheme.Spacing.medium
        }
        .alignmentGuide(.top) { d in
          // Keep the visual center invariant
          d.height / 2 - MarineTheme.Spacing.medium
        }
      }
    }
    .shadow(color: MarineTheme.Colors.shadow, radius: MarineTheme.Metrics.shadowRadius, x: 0, y: MarineTheme.Metrics.shadowOffset)
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
