//
//  SettingsView.swift
//  Sillage
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("General")) {
                    NavigationLink(destination: Text("Map Settings")) {
                        Label("Map Preferences", systemImage: "map")
                            .frame(minHeight: 60)
                            .contentShape(Rectangle())
                    }
                    NavigationLink(destination: Text("Vessel Settings")) {
                        Label("Vessel Details", systemImage: "ferry")
                            .frame(minHeight: 60)
                            .contentShape(Rectangle())
                    }
                }

                Section(header: Text("Safety & Legal")) {
                    NavigationLink(destination: LegalListView(documents: viewModel.legalDocuments)) {
                        Label("Legal & Licenses", systemImage: "doc.text")
                            .frame(minHeight: 60)
                            .contentShape(Rectangle())
                    }
                }

                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    .frame(minHeight: 60)
                    .contentShape(Rectangle())
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
}
