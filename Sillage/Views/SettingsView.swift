//
//  SettingsView.swift
//  Sillage
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("General")) {
                    NavigationLink(destination: Text("Map Settings")) {
                        Label("Map Preferences", systemImage: "map")
                    }
                    NavigationLink(destination: Text("Vessel Settings")) {
                        Label("Vessel Details", systemImage: "ferry")
                    }
                }

                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
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
