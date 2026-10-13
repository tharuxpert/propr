import Permiso
import SwiftUI

/// First run, and the recovery screen when Accessibility permission goes missing.
///
/// Laid out like a Mac setup window: icon, title, explanation, a `GroupBox` for the
/// one thing being asked for, and a single prominent action at the bottom. The
/// previous version nested material cards inside material cards and used a rounded
/// display face, neither of which is a macOS idiom.
struct OnboardingView: View {
    @ObservedObject var accessibility: AccessibilityManager

    /// Called when the user finishes onboarding. Set when presented manually from the
    /// AppDelegate, which is the path used on a cold launch.
    var onComplete: (() -> Void)?

    /// Called when permission flips to granted while this view is visible, so the
    /// presenter can bring the window back to the front.
    var onPermissionGranted: (() -> Void)?

    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        VStack(spacing: 0) {
            header

            GroupBox {
                permissionStatus
            } label: {
                Label("Accessibility Access", systemImage: "accessibility")
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 20)

            actions
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
        }
        .frame(width: 460, height: 460)
        .onAppear { accessibility.startMonitoring() }
        .onDisappear { accessibility.stopMonitoring() }
        .onChange(of: accessibility.hasPermission) { _, granted in
            if granted { onPermissionGranted?() }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 10) {
            Image("BrandIcon")
                .resizable()
                .scaledToFit()
                .frame(width: hasCompletedOnboarding ? 56 : 72, height: hasCompletedOnboarding ? 56 : 72)

            // Returning users are recovering a permission, not being sold the app
            // again, so they get the shorter version.
            Text(hasCompletedOnboarding ? "Accessibility Access Needed" : "Welcome to Propr")
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(
                hasCompletedOnboarding
                    ? "Propr needs Accessibility permission to read and edit text in other apps."
                    : "Refine or look up text anywhere on your Mac. Double-tap ⌘ to refine, or tap Fn on a selection to look it up."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 32)
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
    }

    private var permissionStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                "Propr reads the text field you have focused, and types the result back in. It only looks when you summon it."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(spacing: 8) {
                Image(
                    systemName: accessibility.hasPermission
                        ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(accessibility.hasPermission ? .green : .orange)

                Text(accessibility.hasPermission ? "Granted" : "Not granted yet")
                    .font(.callout)

                if accessibility.isChecking {
                    ProgressView().controlSize(.small)
                }

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
    }

    @ViewBuilder
    private var actions: some View {
        if accessibility.hasPermission {
            VStack(spacing: 10) {
                Text("You're all set. Double-tap ⌘ in any text field, or tap Fn on selected text.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Start Using Propr", action: completeOnboarding)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            Button("Open System Settings…") {
                // Permiso walks the user to the exact row in System Settings, which
                // is otherwise a surprisingly hard place to find.
                PermisoAssistant.shared.present(panel: .accessibility)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true

        if let onComplete {
            onComplete()
        } else {
            dismissWindow(id: "onboarding")
        }

        // Let the window close before anything else takes focus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

#Preview {
    OnboardingView(accessibility: AccessibilityManager.shared)
}
