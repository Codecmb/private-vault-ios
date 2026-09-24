import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct RootView: View {
    @EnvironmentObject var vault: VaultStore

    var body: some View {
        Group {
            if !vault.isConfigured {
                CreateVaultView()
            } else if !vault.isUnlocked {
                UnlockView()
            } else {
                VaultView()
            }
        }
    }
}

struct CreateVaultView: View {
    @EnvironmentObject var vault: VaultStore
    @State private var password = ""
    @State private var confirm = ""
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Create Private Vault") {
                    SecureField("Master password", text: $password)
                    SecureField("Confirm master password", text: $confirm)
                }
                Section {
                    Text("This password is not stored. If you lose it, the vault cannot be recovered.")
                        .font(.footnote)
                }
                Button("Create Vault") {
                    guard password == confirm else { error = "Passwords do not match."; return }
                    do { try vault.create(password: password) }
                    catch { self.error = error.localizedDescription }
                }
                .disabled(password.count < 16)
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Private Vault")
        }
    }
}

struct UnlockView: View {
    @EnvironmentObject var vault: VaultStore
    @State private var password = ""
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                SecureField("Master password", text: $password)
                Button("Unlock") {
                    do {
                        try vault.unlock(password: password)
                        password = ""
                    } catch {
                        self.error = "Unable to unlock vault."
                    }
                }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Vault Locked")
        }
    }
}

struct VaultView: View {
    @EnvironmentObject var vault: VaultStore
    @State private var importing = false
    @State private var previewURL: URL?

    var body: some View {
        NavigationStack {
            List {
                if vault.items.isEmpty {
                    ContentUnavailableView("Vault Empty",
                                           systemImage: "lock.doc",
                                           description: Text("Tap + to add files."))
                } else {
                    ForEach(vault.items) { item in
                        Button {
                            do { previewURL = try vault.decryptedTemporaryURL(for: item) }
                            catch { vault.errorMessage = error.localizedDescription }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(item.displayName)
                                Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                try? vault.delete(item)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
            .navigationTitle("Private Vault")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Lock") { vault.lock() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importing = true } label: { Image(systemName: "plus") }
                }
            }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.item],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    Task { await vault.importFiles(urls) }
                }
            }
            .quickLookPreview($previewURL)
            .alert("Private Vault",
                   isPresented: Binding(get: { vault.errorMessage != nil },
                                        set: { if !$0 { vault.errorMessage = nil } })) {
                Button("OK") { vault.errorMessage = nil }
            } message: {
                Text(vault.errorMessage ?? "")
            }
        }
    }
}
