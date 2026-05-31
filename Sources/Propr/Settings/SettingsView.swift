import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ModelsSettingsView()
                .tabItem {
                    Label("Models", systemImage: "brain")
                }
            
            ScrollView {
                GeneralSettingsView()
            }
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
        }
        // No hard frame here — it fights with the window title bar when hosted manually.
        // Individual tab views control their own comfortable size + padding.
        .padding(.top, 8)
    }
}

struct GeneralSettingsView: View {
    var body: some View {
        VStack {
            Text("General settings coming soon")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    SettingsView()
}