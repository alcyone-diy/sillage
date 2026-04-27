import SwiftUI

@MainActor
struct CommandButtonView: View {
  @Environment(CommandPanelViewModel.self) private var viewModel

  var body: some View {
    @Bindable var bindableViewModel = viewModel
    Button(action: {
      withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
        bindableViewModel.isPanelOpen = true
      }
    }) {
      Image(systemName: "line.3.horizontal")
        .font(.system(size: 24, weight: .bold)) // Keeping font size similar to previous but FAB style manages padding
        .foregroundColor(.white)
    }
    .buttonStyle(MarineFABStyle(backgroundColor: .blue))
  }
}

#Preview {
  CommandButtonView()
    .environment(CommandPanelViewModel())
}
