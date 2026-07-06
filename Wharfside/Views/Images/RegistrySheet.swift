// Views/Images/RegistrySheet.swift

import AppKit
import SwiftUI

struct RegistrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: RegistryListViewModel
    @FocusState private var focusedField: FocusField?

    private enum FocusField: Hashable {
        case registry
        case username
        case password
    }

    init(service: any RegistryServicing) {
        _viewModel = State(initialValue: RegistryListViewModel(service: service))
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            Form {
                Section("Configured registries") {
                    if viewModel.isLoading && viewModel.registries.isEmpty {
                        ProgressView()
                    } else if viewModel.registries.isEmpty {
                        Text("No registry logins configured.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.registries) { registry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(registry.hostname)
                                        .font(.body.monospaced())
                                    if !registry.username.isEmpty {
                                        Text(registry.username)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                Button("Remove", role: .destructive) {
                                    resignFocus()
                                    Task { await viewModel.logout(hostname: registry.hostname) }
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                Section {
                    TextField("Registry", text: $viewModel.registryHost, prompt: Text("docker.io"))
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .registry)
                    TextField("Username", text: $viewModel.username)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .username)
                    SecureField("Password", text: $viewModel.password)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .password)
                        .textContentType(.password)
                } header: {
                    Text("Add login")
                } footer: {
                    Text(
                        "Credentials are stored by the container CLI in the Keychain. "
                            + "Wharfside does not persist them."
                    )
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Registries")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { closeSheet() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sign In") {
                        viewModel.clearError()
                        resignFocus()
                        Task { await viewModel.login() }
                    }
                    .disabled(viewModel.isLoading)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .task { await viewModel.load() }
        }
        .frame(minWidth: 460, minHeight: 420)
    }

    private func closeSheet() {
        resignFocus()
        dismiss()
    }

    private func resignFocus() {
        focusedField = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}
