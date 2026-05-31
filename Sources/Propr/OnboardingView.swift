import SwiftUI
import Permiso

/// Beautiful first-run / permission setup screen.
/// 
/// Style goals: clean, modern, dark-mode friendly, feels native but premium.
/// Different visual language from similar tools (more macOS-native, less "app" chrome).
struct OnboardingView: View {
    @ObservedObject var accessibility: AccessibilityManager

    /// Optional closure to call when the user finishes onboarding.
    /// Used when we present the view manually (e.g. from AppDelegate on first launch).
    /// If nil, we fall back to the declarative dismissWindow.
    var onComplete: (() -> Void)? = nil

    /// Called when the permission status changes to granted while this view is visible.
    /// Used to bring the manual panel back to front after the user grants in System Settings.
    var onPermissionGranted: (() -> Void)? = nil

    @Environment(\.dismissWindow) private var dismissWindow

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        VStack(spacing: 0) {
            // Top icon + header
            VStack(spacing: 12) {
                Image("BrandIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .padding(.top, 32)

                Text("Welcome to Propr")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))

                Text("Refine your writing instantly, anywhere on your Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.bottom, 28)

            // Accessibility permission section — the core of this screen
            VStack(alignment: .leading, spacing: 12) {
                Text("One permission needed")
                    .font(.headline)
                    .padding(.leading, 4)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "accessibility")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Accessibility Access")
                                .font(.subheadline.weight(.medium))

                            Text("Propr needs this to detect text fields and read what you're typing — across every app.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("Tip: If it’s already enabled, remove the entry in System Settings and try again.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                    }

                    // Live permission status
                    HStack(spacing: 10) {
                        Circle()
                            .fill(accessibility.hasPermission ? Color.green : Color.orange)
                            .frame(width: 9, height: 9)

                        Text(accessibility.hasPermission ? "Permission granted" : "Not granted yet")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(accessibility.hasPermission ? .green : .secondary)

                        if accessibility.isChecking {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.leading, 4)
                        }

                        Spacer()

                        if !accessibility.hasPermission {
                            Button("Open System Settings") {
                                PermisoAssistant.shared.present(panel: .accessibility)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.quaternary.opacity(0.6))
                    )
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.regularMaterial)
                )
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 28)

            // Bottom action area
            VStack(spacing: 12) {
                if accessibility.hasPermission {
                    // Success state — smooth transition happens automatically
                    VStack(spacing: 6) {
                        Label("You're all set", systemImage: "checkmark.circle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)

                        Text("Propr can now see focused text fields and help you write better.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .transition(.opacity.combined(with: .scale))
                }

                if accessibility.hasPermission {
                    Button {
                        completeOnboarding()
                    } label: {
                        Text("Start using Propr")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.green)
                    .padding(.horizontal, 32)
                } else {
                    Button {
                        // Use Permiso for a much better guided experience when directing users
                        // to grant Accessibility in System Settings.
                        PermisoAssistant.shared.present(panel: .accessibility)
                    } label: {
                        Text("Open System Settings")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 32)
                }
            }
            .padding(.bottom, 32)
        }
        .frame(width: 460, height: 540)
        .background(.ultraThinMaterial)
        .onAppear {
            accessibility.startMonitoring()
        }
        .onDisappear {
            accessibility.stopMonitoring()
        }
        .onChange(of: accessibility.hasPermission) { _, isGranted in
            if isGranted {
                onPermissionGranted?()
            }
        }
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true

        if let onComplete {
            // Manual presentation path (used on first cold launch from AppDelegate)
            onComplete()
        } else {
            // Declarative Window path (used when clicking "Permissions & Setup..." from menu)
            dismissWindow(id: "onboarding")
        }

        // Small delay so the window closes cleanly before any other UI
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

#Preview {
    OnboardingView(accessibility: AccessibilityManager())
}
