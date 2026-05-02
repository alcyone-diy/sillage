import SwiftUI

@MainActor
struct CommandButtonView: View {
  @Environment(PanelManagerViewModel.self) private var viewModel

  var body: some View {
    @Bindable var bindableViewModel = viewModel
    Button(action: {
      bindableViewModel.openPanel(.command)
    }) {
      Image(systemName: "line.3.horizontal")
        .marineFont(.title2)
        .foregroundColor(.white)
    }
    .buttonStyle(MarineFABStyle(backgroundColor: .blue))
  }
}

#Preview {
  CommandButtonView()
    .environment(PanelManagerViewModel())
}
