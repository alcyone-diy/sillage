import Foundation
import SwiftUI
import Observation

/// A view model managing the state and routing for the Command Panel.
@MainActor
@Observable
public final class CommandPanelViewModel {

  /// Represents the navigation routes within the Command Panel.
  public enum Route: Hashable {
    case settings
  }

  /// Indicates whether the Command Panel is currently visible to the user.
  public var isPanelOpen: Bool = false

  /// The navigation stack path for the Command Panel.
  public var navigationPath: [Route] = []

  public init() {}

  /// Opens the Command Panel.
  public func openPanel() {
    isPanelOpen = true
  }

  /// Closes the Command Panel and resets the routing state.
  public func closePanel() {
    isPanelOpen = false
    resetRouting()
  }

  /// Toggles the visibility of the Command Panel.
  /// If transitioning to closed, the routing state is reset.
  public func togglePanel() {
    if isPanelOpen {
      closePanel()
    } else {
      openPanel()
    }
  }

  /// Resets the navigation path to the root menu.
  private func resetRouting() {
    navigationPath.removeAll()
  }
}
