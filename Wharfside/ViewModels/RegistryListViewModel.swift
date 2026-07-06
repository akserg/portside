// ViewModels/RegistryListViewModel.swift

import Foundation
import Observation

@MainActor
@Observable
final class RegistryListViewModel {
    private(set) var registries: [RegistryEntry] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var registryHost = ""
    var username = ""
    var password = ""

    private let service: any RegistryServicing

    init(service: any RegistryServicing) {
        self.service = service
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            registries = try await service.list()
            errorMessage = nil
        } catch {
            errorMessage = ErrorMapper.map(error).localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func login() async {
        let host = registryHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !user.isEmpty, !password.isEmpty else {
            errorMessage = "Registry, username, and password are required."
            return
        }

        isLoading = true
        defer {
            isLoading = false
            password = ""
        }

        do {
            try await service.login(registry: host, username: user, password: password)
            registryHost = ""
            username = ""
            errorMessage = nil
            await load()
        } catch {
            errorMessage = sanitizedLoginError(ErrorMapper.map(error))
        }
    }

    func logout(hostname: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await service.logout(registry: hostname)
            errorMessage = nil
            await load()
        } catch {
            errorMessage = ErrorMapper.map(error).localizedDescription
        }
    }

    private func sanitizedLoginError(_ error: WharfsideError) -> String {
        error.localizedDescription
    }
}
