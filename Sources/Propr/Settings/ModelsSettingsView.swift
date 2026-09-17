import SwiftUI

struct ModelsSettingsView: View {
    @State var modelStore = ModelStore.shared

    @State var showingAddForm = false

    // Quick Add state
    @State var quickAddProvider: BuiltInProvider?
    @State var quickAddAPIKey = ""
    @State var quickAddBaseURL = ""  // editable for Local provider (Ollama/LM Studio etc.)

    // One form value per flow. Both use the same rules (see EndpointFormState);
    // the quick-add flow shares the add form's model list.
    @State var addForm = EndpointFormState()

    @State var editingEndpointID: UUID?
    @State var editForm = EndpointFormState()

    /// Set when a Keychain write fails, so the user is told instead of the
    /// failure being swallowed into a console log.
    @State var keychainErrorMessage: String?

    /// What the add form validates against: every existing endpoint.
    var addContext: EndpointFormState.ValidationContext {
        .init(existingEndpoints: modelStore.customEndpoints)
    }

    /// What the edit form validates against: every existing endpoint except the one
    /// being edited, which must not count as a duplicate of itself.
    func editContext(for endpoint: CustomEndpoint) -> EndpointFormState.ValidationContext {
        .init(existingEndpoints: modelStore.customEndpoints, excludingEndpointID: endpoint.id)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Removed the "Models" title here — the TabView tab already labels this section,
                    // and having it caused ugly double-labeling + truncation near the window title bar.

                    // Quick Start (Built-in providers)
                    // Non-lazy grid to avoid cells disappearing during fast scroll when the
                    // quick-add form below is open (LazyVGrid + dynamic content height change
                    // below it is a known source of recycling glitches).
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick Start")
                            .font(.headline)

                        Text("Popular providers — just paste your API key.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        // Stable non-lazy rows (8 providers → max 3 per row). Eliminates the
                        // fast-scroll disappearance bug while the quick-add form is visible.
                        let providers = BuiltInProvider.all
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(stride(from: 0, to: providers.count, by: 3)), id: \.self)
                            {
                                start in
                                HStack(spacing: 10) {
                                    ForEach(0..<3, id: \.self) { offset in
                                        let index = start + offset
                                        if index < providers.count {
                                            QuickStartCard(provider: providers[index]) { startQuickAdd(for: providers[index]) }
                                        } else {
                                            Spacer()
                                                .frame(maxWidth: .infinity)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .animation(nil, value: showingAddForm)
                    .animation(nil, value: quickAddProvider != nil)

                    quickAddForm
                    // Custom Endpoint (BYOK)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Bring Your Own Key (BYOK)")
                            .font(.headline)

                        Button {
                            showingAddForm.toggle()
                            if !showingAddForm {
                                resetAddForm()
                            }
                        } label: {
                            Label("Add custom endpoint", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)

                        // Inline add form (smoothly appears)
                        // We scope the animation to *this* VStack only so the Quick Start
                        // cards above don't get unwanted layout animation when the form expands.
                        if showingAddForm {
                            addEndpointForm
                                // Use scale from the top instead of .move(edge: .top) so the form
                                // expands downward in place and never visually flies in from above
                                // the BYOK section (avoiding overlap on Quick Start cards).
                                .transition(
                                    .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                                )
                                .padding(.top, 8)
                        }
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingAddForm)

                    // Existing custom endpoints
                    if !modelStore.customEndpoints.isEmpty {
                        Text("Your Endpoints")
                            .font(.headline)

                        ForEach(modelStore.customEndpoints) { endpoint in
                            EndpointRow(
                                endpoint: endpoint,
                                onEdit: { startEditingEndpoint(endpoint) },
                                onDelete: {
                                    if editingEndpointID == endpoint.id {
                                        cancelEditingEndpoint()
                                    }
                                    modelStore.deleteEndpoint(id: endpoint.id)
                                }
                            )

                            if editingEndpointID == endpoint.id {
                                editEndpointForm(for: endpoint)
                                    .transition(
                                        .opacity.combined(with: .scale(scale: 0.98, anchor: .top)))

                                Color.clear
                                    .frame(height: 1)
                                    .id(editFormID(for: endpoint.id))
                                    .onAppear {
                                        scrollToEditForm(endpoint.id, with: scrollProxy)
                                    }
                            }
                        }
                    } else if !showingAddForm {
                        Spacer()

                        VStack(spacing: 16) {
                            Image(systemName: "network")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)

                            Text("No custom endpoints yet")
                                .font(.headline)

                            Text("Add your first OpenAI-compatible endpoint above.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)

                        Spacer()
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .onChange(of: editingEndpointID) { _, endpointID in
                guard let endpointID else { return }
                scrollToEditForm(endpointID, with: scrollProxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 520)
        .alert(
            "Could not save the API key",
            isPresented: Binding(
                get: { keychainErrorMessage != nil },
                set: { if !$0 { keychainErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { keychainErrorMessage = nil }
        } message: {
            // Keys go to the Keychain, where a save can genuinely fail (locked
            // keychain, denied access). Failing silently would leave the endpoint
            // looking configured while refining reports a missing key.
            Text(keychainErrorMessage ?? "")
        }
    }

}

#Preview {
    ModelsSettingsView()
}
