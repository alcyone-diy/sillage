//
//  SettingsView.swift
//  Alcyone Sillage
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppViewModel.self) private var appViewModel
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("General")) {
                    @Bindable var bindableAppViewModel = appViewModel
                    Toggle(isOn: $bindableAppViewModel.isGloveModeEnabled) {
                        Label("Glove Mode", systemImage: "hand.raised.fill")
                    }
                    .marineListCell()

                    NavigationLink(destination: Text("Map Settings")) {
                        Label("Map Preferences", systemImage: "map")
                            .marineListCell()
                    }
                    NavigationLink(destination: Text("Vessel Settings")) {
                        Label("Vessel Details", systemImage: "ferry")
                            .marineListCell()
                    }
                }

                Section(header: Text("Safety & Legal")) {
                    NavigationLink(destination: LegalListView(documents: viewModel.legalDocuments)) {
                        Label("Legal & Licenses", systemImage: "doc.text")
                            .marineListCell()
                    }
                }

                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    .marineListCell()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppViewModel())
        .environment(\.marineUIStyle, .standard)
}
