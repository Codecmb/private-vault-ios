import SwiftUI
import UniformTypeIdentifiers
import QuickLook

extension UTType {
    static var privateVaultBackup: UTType { UTType(exportedAs: "com.privatevault.backup") }
}

struct RootView: View {
    @EnvironmentObject var vault: VaultStore
    var body: some View {
        Group {
            if !vault.isConfigured { CreateVaultView() }
            else if !vault.isUnlocked { UnlockView() }
            else { VaultView() }
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
                Text("Use a unique password of at least 16 characters. It is not stored and cannot be recovered.")
                    .font(.footnote)
                Button("Create Vault") {
                    guard password == confirm else { error = "Passwords do not match."; return }
                    do { try vault.create(password: password) }
                    catch { self.error = error.localizedDescription }
                }.disabled(password.count < 16)
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Private Vault")
        }
    }
}

struct UnlockView: View {
    @EnvironmentObject var vault: VaultStore
    @State private var password = ""
    @State private var error = ""
    @State private var restoring = false

    var body: some View {
        NavigationStack {
            Form {
                SecureField("Master password", text: $password)
                Button("Unlock") {
                    do { try vault.unlock(password: password); password = "" }
                    catch { self.error = "Unable to unlock vault." }
                }
                Button("Restore Encrypted Backup") { restoring = true }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Vault Locked")
            .fileImporter(isPresented: $restoring, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    do { try vault.restoreEncryptedBackup(from: url) }
                    catch { error = "Restore failed: \(error.localizedDescription)" }
                }
            }
        }
    }
}

struct VaultView: View {
    @EnvironmentObject var vault: VaultStore
    @State private var importing = false
    @State private var previewURL: URL?
    @State private var newFolder = ""
    @State private var showNewFolder = false
    @State private var backupURL: URL?
    @State private var showShare = false
    @State private var showPasswordChange = false

    var body: some View {
        NavigationStack {
            List {
                if !vault.folders.isEmpty {
                    Section("Folders") {
                        ForEach(vault.folders) { folder in
                            Label(folder.name, systemImage: "folder.fill")
                        }
                    }
                }
                Section("Files") {
                    if vault.items.isEmpty {
                        ContentUnavailableView("Vault Empty", systemImage: "lock.doc",
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
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) { try? vault.delete(item) }
                                label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Private Vault")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Lock") { vault.lock() } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button("Add Files", systemImage: "doc.badge.plus") { importing = true }
                        Button("New Folder", systemImage: "folder.badge.plus") { showNewFolder = true }
                        Button("Export Encrypted Backup", systemImage: "externaldrive") {
                            do { backupURL = try vault.makeEncryptedBackup(); showShare = true }
                            catch { vault.errorMessage = error.localizedDescription }
                        }
                        Button("Change Master Password", systemImage: "key") { showPasswordChange = true }
                    } label: { Image(systemName: "plus.circle") }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { Task { await vault.importFiles(urls) } }
            }
            .quickLookPreview($previewURL)
            .alert("New Folder", isPresented: $showNewFolder) {
                TextField("Folder name", text: $newFolder)
                Button("Create") { try? vault.addFolder(name: newFolder); newFolder = "" }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showShare) {
                if let backupURL { ShareSheet(items: [backupURL]) }
            }
            .sheet(isPresented: $showPasswordChange) { ChangePasswordView() }
            .alert("Private Vault",
                   isPresented: Binding(get: { vault.errorMessage != nil },
                                        set: { if !$0 { vault.errorMessage = nil } })) {
                Button("OK") { vault.errorMessage = nil }
            } message: { Text(vault.errorMessage ?? "") }
        }
    }
}

struct ChangePasswordView: View {
    @EnvironmentObject var vault: VaultStore
    @Environment(\.dismiss) var dismiss
    @State private var old = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                SecureField("Current master password", text: $old)
                SecureField("New master password", text: $new)
                SecureField("Confirm new password", text: $confirm)
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
                Button("Change Password") {
                    guard new == confirm else { error = "New passwords do not match."; return }
                    do { try vault.changeMasterPassword(oldPassword: old, newPassword: new); dismiss() }
                    catch { self.error = "Password change failed." }
                }.disabled(new.count < 16)
            }.navigationTitle("Change Password")
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
