import SwiftUI

@MainActor
struct CommandPanelView: View {
  @Environment(CommandPanelViewModel.self) private var viewModel
  @Environment(\.marineTheme) private var marineTheme

  var body: some View {
    @Bindable var bindableViewModel = viewModel

    NavigationStack(path: $bindableViewModel.navigationPath) {
      List {
        Button(action: {
          bindableViewModel.navigationPath.append(CommandPanelViewModel.Route.settings)
        }) {
          HStack {
            Image(systemName: "gearshape.fill")
              .foregroundColor(.secondary)
            Text("Settings")
              .marineFont(.body)
              .foregroundColor(.primary)
          }
        }
        .marineListCell()
      }
      .scrollContentBackground(.hidden)
      .navigationTitle("Command Panel")
      .navigationBarTitleDisplayMode(.inline)
      .navigationDestination(for: CommandPanelViewModel.Route.self) { route in
        switch route {
        case .settings:
          SettingsView()
        }
      }
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button(action: {
            withAnimation(.spring(duration: 0.35, bounce: 0.0)) {
              bindableViewModel.isPanelOpen = false
            }
          }) {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(.tertiary)
              .font(.title2)
          }
        }
      }
      .background(.thickMaterial)
    }
  }
}

#Preview {
  CommandPanelView()
    .environment(CommandPanelViewModel())
    .environment(\.marineTheme, .standard)
}
