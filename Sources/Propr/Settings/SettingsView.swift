import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general
    case models

    var title: String {
        switch self {
        case .models: return "Models"
        case .general: return "General"
        }
    }

    var systemImage: String {
        switch self {
        case .models: return "brain"
        case .general: return "gearshape"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Tab bar (natural height)
                HStack {
                    Spacer(minLength: 0)

                    HStack(spacing: 16) {
                        ForEach(SettingsTab.allCases, id: \.self) { tab in
                            VStack(spacing: 3) {
                                ZStack {
                                    if selectedTab == tab {
                                        RoundedRectangle(cornerRadius: 9)
                                            .fill(Color.accentColor.opacity(0.22))
                                            .frame(width: 50, height: 38)
                                    }
                                    Image(systemName: tab.systemImage)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                                }
                                .frame(width: 50, height: 38)

                                Text(tab.title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedTab = tab
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background(.regularMaterial)
                .onChange(of: selectedTab) { newTab in
                    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" }) {
                        window.title = newTab.title
                    }
                }
                .onAppear {
                    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" }) {
                        window.title = selectedTab.title
                    }
                }

                Divider()

                // Content area sized explicitly from the remaining window height
                Group {
                    switch selectedTab {
                    case .models:
                        ModelsSettingsView()
                    case .general:
                        ScrollView {
                            GeneralSettingsView()
                        }
                    }
                }
                .frame(
                    width: geo.size.width,
                    height: max(400, geo.size.height - 70) // safety min height so content is never zero
                )
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
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