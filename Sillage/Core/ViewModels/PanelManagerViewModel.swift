import Foundation
import SwiftUI
import Observation

/// A view model managing the state and routing for UI panels.
@MainActor
@Observable
public final class PanelManagerViewModel {

  public enum ActivePanel: Equatable {
    case none
    case command
    case telemetry
  }

  /// Represents the navigation routes within the Command Panel.
  public enum Route: Hashable {
    case settings
  }

  /// The currently active panel visible to the user.
  public var activePanel: ActivePanel = .none

  /// The navigation stack path for the Command Panel.
  public var commandNavigationPath: [Route] = []

  public init() {}

  /// Opens the specified panel.
  public func openPanel(_ panel: ActivePanel) {
    withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
      activePanel = panel
    }
  }

  /// Closes any active panel and resets the routing state after the animation completes.
  public func closePanel() {
    // iOS 17+ native completion handler
    withAnimation(.spring(response: 0.45, dampingFraction: 1.0)) {
      activePanel = .none
    } completion: {
      // Clean up routing only AFTER the panel is completely off-screen
      self.resetRouting()
    }
  }

  /// Toggles the visibility of the specified panel.
  /// If it is already active, it is closed. Otherwise, it is opened.
  public func togglePanel(_ panel: ActivePanel) {
    if activePanel == panel {
      closePanel()
    } else {
      openPanel(panel)
    }
  }

  /// Resets the navigation path to the root menu.
  private func resetRouting() {
    commandNavigationPath.removeAll()
  }
}
