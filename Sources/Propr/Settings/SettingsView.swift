import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ModelsSettingsView()
                .tabItem {
                    Label("Models", systemImage: "brain")
                }
            
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
        }
        .frame(width: 580, height: 480)
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