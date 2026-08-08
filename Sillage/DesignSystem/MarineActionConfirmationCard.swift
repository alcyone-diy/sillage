//
//  MarineActionConfirmationCard.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Technical Design Choice: Modular Marine Action Confirmation Card
///
/// 1. **Marine UX & Fitts's Law (Glove Mode):**
///    Crucial action prompts used in offshore sailing (e.g. anchor relocation, waypoint position adjustments, map downloads)
///    must be easily operable under vibration and with wet/gloved hands. All buttons enforce `marineTheme.minTouchTarget` (66pt+ in Glove Mode).
///
/// 2. **Generic Header & Architectural Flexibility:**
///    Using a generic `Content: View` parameter allows this card to render both simple text instruction prompts
///    (via `init(title: ...)`) and complex interactive sub-views (e.g., live telemetry feedback, crop bounding box dimensions, download size estimates).
///
/// 3. **High Glare & Adaptive Contrast:**
///    Uses `Material.ultraThinMaterial` backdrops combined with `MarineTheme` tokenized colors (`vectorHDG`, `surfaceBackground`, `onPrimary`)
///    to guarantee high legibility under direct sunlight glare while preserving map background context.
public struct MarineActionConfirmationCard<Content: View>: View {
  @Environment(\.marineTheme) private var marineTheme

  private let headerContent: Content
  private let cancelTitle: LocalizedStringKey?
  private let cancelIcon: String?
  private let cancelStyle: Color?
  private let cancelForegroundColor: Color?
  private let onCancel: (@MainActor () -> Void)?

  private let confirmTitle: LocalizedStringKey
  private let confirmIcon: String?
  private let confirmStyle: Color?
  private let confirmForegroundColor: Color?
  private let isConfirmDisabled: Bool
  private let onConfirm: @MainActor () -> Void
  private let onHeightChange: ((CGFloat) -> Void)?

  /// Creates a modular action confirmation card with custom header content.
  /// - Parameters:
  ///   - cancelTitle: Optional title for the cancel action button. Default is `"Cancel"`. Pass `nil` to omit the cancel button.
  ///   - cancelIcon: Optional SF Symbol icon name for the cancel button. Default is `"xmark"`.
  ///   - cancelStyle: Optional custom background color for the cancel button. Defaults to `surfaceBackground`.
  ///   - cancelForegroundColor: Optional custom text/icon color for the cancel button. Defaults to `textSecondary`.
  ///   - onCancel: Optional main-actor closure called when the user taps the cancel button.
  ///   - confirmTitle: Title for the confirm action button. Default is `"Confirm"`.
  ///   - confirmIcon: Optional SF Symbol icon name for the confirm button. Default is `"checkmark"`.
  ///   - confirmStyle: Optional custom background color for the confirm button. Defaults to `primary`.
  ///   - confirmForegroundColor: Optional custom text/icon color for the confirm button. Defaults to `onPrimary`.
  ///   - isConfirmDisabled: Whether the confirm button is disabled. Default is `false`.
  ///   - onConfirm: Main-actor closure called when the user taps the confirm button.
  ///   - onHeightChange: Optional closure receiving rendered card height changes for dynamic parent layout spacing.
  ///   - headerContent: A ViewBuilder returning custom content displayed above the action buttons.
  public init(
    cancelTitle: LocalizedStringKey? = "Cancel",
    cancelIcon: String? = "xmark",
    cancelStyle: Color? = nil,
    cancelForegroundColor: Color? = nil,
    onCancel: (@MainActor () -> Void)? = nil,
    confirmTitle: LocalizedStringKey = "Confirm",
    confirmIcon: String? = "checkmark",
    confirmStyle: Color? = nil,
    confirmForegroundColor: Color? = nil,
    isConfirmDisabled: Bool = false,
    onConfirm: @MainActor @escaping () -> Void,
    onHeightChange: ((CGFloat) -> Void)? = nil,
    @ViewBuilder headerContent: () -> Content
  ) {
    self.cancelTitle = cancelTitle
    self.cancelIcon = cancelIcon
    self.cancelStyle = cancelStyle
    self.cancelForegroundColor = cancelForegroundColor
    self.onCancel = onCancel
    self.confirmTitle = confirmTitle
    self.confirmIcon = confirmIcon
    self.confirmStyle = confirmStyle
    self.confirmForegroundColor = confirmForegroundColor
    self.isConfirmDisabled = isConfirmDisabled
    self.onConfirm = onConfirm
    self.onHeightChange = onHeightChange
    self.headerContent = headerContent()
  }

  public var body: some View {
    VStack(spacing: MarineTheme.Spacing.medium) {
      headerContent

      HStack(spacing: MarineTheme.Spacing.medium) {
        if let cancelTitle = cancelTitle, let onCancel = onCancel {
          Button(action: onCancel) {
            HStack(spacing: MarineTheme.Spacing.small) {
              if let icon = cancelIcon {
                Image(systemName: icon)
              }
              Text(cancelTitle)
            }
            .font(.headline.bold())
            .frame(maxWidth: .infinity, minHeight: marineTheme.minTouchTarget)
            .background(cancelStyle ?? marineTheme.colors.surfaceBackground)
            .foregroundColor(cancelForegroundColor ?? marineTheme.colors.textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous))
          }
          .buttonStyle(MarineButtonStyle())
        }

        Button(action: onConfirm) {
          HStack(spacing: MarineTheme.Spacing.small) {
            if let icon = confirmIcon {
              Image(systemName: icon)
            }
            Text(confirmTitle)
          }
          .font(.headline.bold())
          .frame(maxWidth: .infinity, minHeight: marineTheme.minTouchTarget)
          .background(
            isConfirmDisabled
              ? marineTheme.colors.disabledBackground
              : (confirmStyle ?? marineTheme.colors.primary)
          )
          .foregroundColor(
            isConfirmDisabled
              ? marineTheme.colors.textSecondary
              : (confirmForegroundColor ?? marineTheme.colors.onPrimary)
          )
          .clipShape(RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(MarineButtonStyle())
        .disabled(isConfirmDisabled)
      }
    }
    .padding(MarineTheme.Spacing.medium)
    .background(Material.ultraThinMaterial)
    .cornerRadius(MarineTheme.Metrics.cornerRadius)
    .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
    .onGeometryChange(for: CGFloat.self) { proxy in
      proxy.size.height
    } action: { newHeight in
      onHeightChange?(newHeight)
    }
    .onDisappear {
      onHeightChange?(0)
    }
  }
}

// MARK: - Instruction Header View
public struct MarineCardInstructionTitle: View {
  let title: LocalizedStringKey
  @Environment(\.marineTheme) private var marineTheme

  public init(title: LocalizedStringKey) {
    self.title = title
  }

  public var body: some View {
    Text(title)
      .font(.subheadline.bold())
      .foregroundColor(marineTheme.colors.textSecondary)
      .multilineTextAlignment(.center)
  }
}

// MARK: - Standard Text Header Convenience Extension
extension MarineActionConfirmationCard where Content == MarineCardInstructionTitle {
  /// Creates a modular action confirmation card with a standard instruction text header.
  /// - Parameters:
  ///   - title: The instructional text or prompt displayed at the top of the card.
  ///   - cancelTitle: Optional title for the cancel action button. Default is `"Cancel"`.
  ///   - cancelIcon: Optional SF Symbol icon name for the cancel button. Default is `"xmark"`.
  ///   - cancelStyle: Optional custom background color for the cancel button.
  ///   - cancelForegroundColor: Optional custom text/icon color for the cancel button.
  ///   - onCancel: Optional main-actor closure called when the user taps the cancel button.
  ///   - confirmTitle: Title for the confirm action button. Default is `"Confirm"`.
  ///   - confirmIcon: Optional SF Symbol icon name for the confirm button. Default is `"checkmark"`.
  ///   - confirmStyle: Optional custom background color for the confirm button.
  ///   - confirmForegroundColor: Optional custom text/icon color for the confirm button.
  ///   - isConfirmDisabled: Whether the confirm button is disabled. Default is `false`.
  ///   - onConfirm: Main-actor closure called when the user taps the confirm button.
  ///   - onHeightChange: Optional closure receiving rendered card height changes for dynamic parent layout spacing.
  public init(
    title: LocalizedStringKey,
    cancelTitle: LocalizedStringKey? = "Cancel",
    cancelIcon: String? = "xmark",
    cancelStyle: Color? = nil,
    cancelForegroundColor: Color? = nil,
    onCancel: (@MainActor () -> Void)? = nil,
    confirmTitle: LocalizedStringKey = "Confirm",
    confirmIcon: String? = "checkmark",
    confirmStyle: Color? = nil,
    confirmForegroundColor: Color? = nil,
    isConfirmDisabled: Bool = false,
    onConfirm: @MainActor @escaping () -> Void,
    onHeightChange: ((CGFloat) -> Void)? = nil
  ) {
    self.init(
      cancelTitle: cancelTitle,
      cancelIcon: cancelIcon,
      cancelStyle: cancelStyle,
      cancelForegroundColor: cancelForegroundColor,
      onCancel: onCancel,
      confirmTitle: confirmTitle,
      confirmIcon: confirmIcon,
      confirmStyle: confirmStyle,
      confirmForegroundColor: confirmForegroundColor,
      isConfirmDisabled: isConfirmDisabled,
      onConfirm: onConfirm,
      onHeightChange: onHeightChange
    ) {
      MarineCardInstructionTitle(title: title)
    }
  }
}
