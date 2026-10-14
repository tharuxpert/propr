import SwiftUI

/// The Settings tab strip: one tab per pane, icon over label, the way modern Mac
/// utilities lay their settings out. Replaces the sidebar, so the window is a single
/// pane wide and every pane is one click or one arrow key away.
struct SettingsTabStrip: View {
    @Binding var selection: SettingsSection

    @FocusState private var isStripFocused: Bool
    @Namespace private var glassNamespace

    var body: some View {
        tabs
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) { Divider() }
            // Arrow keys change the pane, which is what the old sidebar's List gave
            // us. The strip is focusable for that, with the focus ring suppressed so
            // it never looks like a control that is about to do something.
            .focusable()
            .focusEffectDisabled()
            .focused($isStripFocused)
            .onMoveCommand(perform: move)
            .defaultFocus($isStripFocused, true)
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(macOS 26.0, *) {
            // One container so the selected pill morphs from tab to tab instead of
            // fading in and out.
            GlassEffectContainer(spacing: 6) { tabRow }
        } else {
            tabRow
        }
    }

    private var tabRow: some View {
        HStack(spacing: 6) {
            ForEach(SettingsSection.allCases) { section in
                tab(section)
            }
        }
    }

    private func tab(_ section: SettingsSection) -> some View {
        let isSelected = section == selection
        return Button {
            selection = section
        } label: {
            VStack(spacing: 4) {
                SettingsIcon(
                    systemImage: section.systemImage,
                    color: isSelected ? section.color : .gray,
                    size: 22
                )
                Text(section.title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .frame(width: 92)
            .padding(.vertical, 5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .modifier(SelectedTabPill(isSelected: isSelected, id: section, namespace: glassNamespace))
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func move(_ direction: MoveCommandDirection) {
        switch direction {
        case .left: selection = SettingsSection.moved(from: selection, by: -1)
        case .right: selection = SettingsSection.moved(from: selection, by: 1)
        default: break
        }
    }
}

extension SettingsSection {
    /// The tab `steps` away in the strip, wrapping around the ends.
    static func moved(from current: SettingsSection, by steps: Int) -> SettingsSection {
        let all = allCases
        guard let index = all.firstIndex(of: current), !all.isEmpty else { return current }
        let target = (index + steps % all.count + all.count) % all.count
        return all[target]
    }
}

/// The pill behind the selected tab. On macOS 26 it is real Liquid Glass, tinted with
/// the tab's colour and interactive so it responds to the pointer; on older systems it
/// falls back to the plain highlight every Mac app has used for years.
private struct SelectedTabPill: ViewModifier {
    let isSelected: Bool
    let id: SettingsSection
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    isSelected ? .regular.tint(id.color.opacity(0.45)).interactive() : .identity,
                    in: .capsule
                )
                // Keeps the pill's identity across tab changes so the glass can morph.
                .glassEffectID(id, in: namespace)
        } else {
            content.background {
                if isSelected {
                    Capsule(style: .continuous).fill(Color.primary.opacity(0.12))
                }
            }
        }
    }
}

#Preview {
    SettingsTabStrip(selection: .constant(.refine))
        .frame(width: 620, height: 90)
}
