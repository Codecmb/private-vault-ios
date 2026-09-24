import Foundation
import Combine
import CryptoKit
import UniformTypeIdentifiers

@MainActor
final class VaultStore: ObservableObject {
    @Published var isConfigured = false
    @Published var isUnlocked = false
    @Published var items: [VaultItem] = []
    @Published var folders: [VaultFolder] = []
    @Published var errorMessage: String?

    private var vaultKey: SymmetricKey?
    private let fm = FileManager.default

    private var baseURL: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrivateVault", isDirectory: true)
    }
    private var blobsURL: URL { baseURL.appendingPathComponent("blobs", isDirectory: true) }
    private var headerURL: URL { baseURL.appendingPathComponent("header.json") }
    private var manifestURL: URL { baseURL.appendingPathComponent("manifest.enc") }

    init() {
        purgeTemporaryPreviews()
        isConfigured = fm.fileExists(atPath: headerURL.path)
    }

    func create(password: String) throws {
        guard password.count >= 16 else { throw userError("Use at least 16 characters.") }
        try fm.createDirectory(at: blobsURL, withIntermediateDirectories: true)
        let salt = CryptoService.randomData(count: CryptoService.saltBytes)
        let passwordKey = try CryptoService.deriveKey(password: password, salt: salt, iterations: CryptoService.iterations)
        let rawVaultKey = CryptoService.randomData(count: CryptoService.keyBytes)
        let newVaultKey = SymmetricKey(data: rawVaultKey)
        let wrapped = try CryptoService.seal(rawVaultKey, using: passwordKey)
        let header = VaultHeader(salt: salt, iterations: CryptoService.iterations, wrappedVaultKey: wrapped)
        try protectedWrite(JSONEncoder().encode(header), to: headerURL)
        vaultKey = newVaultKey
        items = []
        folders = []
        try saveManifest()
        isConfigured = true
        isUnlocked = true
    }

    func unlock(password: String) throws {
        let header = try JSONDecoder().decode(VaultHeader.self, from: Data(contentsOf: headerURL))
        let passwordKey = try CryptoService.deriveKey(password: password, salt: header.salt, iterations: header.iterations)
        let raw = try CryptoService.open(header.wrappedVaultKey, using: passwordKey)
        let key = SymmetricKey(data: raw)
        let plainManifest = try CryptoService.open(Data(contentsOf: manifestURL), using: key)
        let manifest = try JSONDecoder().decode(VaultManifest.self, from: plainManifest)
        vaultKey = key
        items = manifest.items
        folders = manifest.folders
        isUnlocked = true
    }

    func lock() {
        purgeTemporaryPreviews()
        vaultKey = nil
        items = []
        folders = []
        isUnlocked = false
    }

    func addFolder(name: String) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        folders.append(VaultFolder(id: UUID(), name: clean, createdAt: Date()))
        try saveManifest()
    }

    func changeMasterPassword(oldPassword: String, newPassword: String) throws {
        guard newPassword.count >= 16 else { throw userError("Use at least 16 characters.") }
        let header = try JSONDecoder().decode(VaultHeader.self, from: Data(contentsOf: headerURL))
        let oldKey = try CryptoService.deriveKey(password: oldPassword, salt: header.salt, iterations: header.iterations)
        let rawVaultKey = try CryptoService.open(header.wrappedVaultKey, using: oldKey)

        let newSalt = CryptoService.randomData(count: CryptoService.saltBytes)
        let newPasswordKey = try CryptoService.deriveKey(password: newPassword, salt: newSalt, iterations: CryptoService.iterations)
        let wrapped = try CryptoService.seal(rawVaultKey, using: newPasswordKey)
        let newHeader = VaultHeader(salt: newSalt, iterations: CryptoService.iterations, wrappedVaultKey: wrapped)
        try protectedWrite(JSONEncoder().encode(newHeader), to: headerURL)
    }

    func importFiles(_ urls: [URL], folderID: UUID? = nil) async {
        guard let key = vaultKey else { return }
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let encrypted = try CryptoService.seal(data, using: key)
                let storedName = UUID().uuidString + ".blob"
                try protectedWrite(encrypted, to: blobsURL.appendingPathComponent(storedName))
                items.append(VaultItem(id: UUID(), displayName: url.lastPathComponent,
                                       storedName: storedName, createdAt: Date(),
                                       size: Int64(data.count), folderID: folderID))
                try saveManifest()
            } catch { errorMessage = "Import failed: \(error.localizedDescription)" }
        }
    }

    func decryptedTemporaryURL(for item: VaultItem) throws -> URL {
        guard let key = vaultKey else { throw VaultCryptoError.invalidPassword }
        let encrypted = try Data(contentsOf: blobsURL.appendingPathComponent(item.storedName))
        let clear = try CryptoService.open(encrypted, using: key)
        let tempDir = previewRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let out = tempDir.appendingPathComponent(item.displayName)
        try clear.write(to: out, options: [.atomic, .completeFileProtection])
        return out
    }

    func delete(_ item: VaultItem) throws {
        let blobURL = blobsURL.appendingPathComponent(item.storedName)
        if fm.fileExists(atPath: blobURL.path) {
            try fm.removeItem(at: blobURL)
        }
        items.removeAll { $0.id == item.id }
        try saveManifest()
    }

    func makeEncryptedBackup() throws -> URL {
        let header = try JSONDecoder().decode(VaultHeader.self, from: Data(contentsOf: headerURL))
        let encryptedManifest = try Data(contentsOf: manifestURL)
        let blobs = try items.map { item -> BackupBlob in
            let data = try Data(contentsOf: blobsURL.appendingPathComponent(item.storedName))
            return BackupBlob(storedName: item.storedName, ciphertext: data)
        }
        let backup = VaultBackup(header: header, encryptedManifest: encryptedManifest, blobs: blobs)
        let data = try JSONEncoder().encode(backup)
        let out = fm.temporaryDirectory.appendingPathComponent("PrivateVault-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")).pvault")
        try data.write(to: out, options: [.atomic, .completeFileProtection])
        return out
    }

    func restoreEncryptedBackup(from url: URL, password: String) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        let backup = try JSONDecoder().decode(
            VaultBackup.self,
            from: Data(contentsOf: url)
        )
        guard backup.version == 1 else {
            throw userError("Unsupported backup version.")
        }

        // Validate the backup and password BEFORE replacing the current vault.
        let passwordKey = try CryptoService.deriveKey(
            password: password,
            salt: backup.header.salt,
            iterations: backup.header.iterations
        )
        let rawVaultKey = try CryptoService.open(
            backup.header.wrappedVaultKey,
            using: passwordKey
        )
        let backupVaultKey = SymmetricKey(data: rawVaultKey)
        let plainManifest = try CryptoService.open(
            backup.encryptedManifest,
            using: backupVaultKey
        )
        let manifest = try JSONDecoder().decode(
            VaultManifest.self,
            from: plainManifest
        )

        guard manifest.version == 2 else {
            throw userError("Unsupported vault version.")
        }

        let expectedBlobs = Set(manifest.items.map(\.storedName))
        let suppliedBlobs = Set(backup.blobs.map(\.storedName))

        guard expectedBlobs == suppliedBlobs,
              expectedBlobs.count == backup.blobs.count else {
            throw userError("Backup is incomplete or malformed.")
        }

        let staging = baseURL.deletingLastPathComponent()
            .appendingPathComponent(
                "PrivateVault-Restore-\(UUID().uuidString)",
                isDirectory: true
            )
        let stagingBlobs = staging.appendingPathComponent(
            "blobs",
            isDirectory: true
        )

        try fm.createDirectory(
            at: stagingBlobs,
            withIntermediateDirectories: true
        )

        do {
            try protectedWrite(
                JSONEncoder().encode(backup.header),
                to: staging.appendingPathComponent("header.json")
            )
            try protectedWrite(
                backup.encryptedManifest,
                to: staging.appendingPathComponent("manifest.enc")
            )

            for blob in backup.blobs {
                // Verify every encrypted file before installing the backup.
                _ = try CryptoService.open(
                    blob.ciphertext,
                    using: backupVaultKey
                )
                try protectedWrite(
                    blob.ciphertext,
                    to: stagingBlobs.appendingPathComponent(blob.storedName)
                )
            }
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }

        let old = baseURL.deletingLastPathComponent()
            .appendingPathComponent(
                "PrivateVault-Old-\(UUID().uuidString)",
                isDirectory: true
            )

        if fm.fileExists(atPath: baseURL.path) {
            try fm.moveItem(at: baseURL, to: old)
        }

        do {
            try fm.moveItem(at: staging, to: baseURL)
            try? fm.removeItem(at: old)
            lock()
            isConfigured = true
        } catch {
            try? fm.removeItem(at: baseURL)

            if fm.fileExists(atPath: old.path) {
                try? fm.moveItem(at: old, to: baseURL)
            }

            throw error
        }
    }

    private func saveManifest() throws {
        guard let key = vaultKey else { return }
        let plain = try JSONEncoder().encode(VaultManifest(folders: folders, items: items))
        try protectedWrite(try CryptoService.seal(plain, using: key), to: manifestURL)
    }

    private var previewRoot: URL {
        fm.temporaryDirectory.appendingPathComponent("PrivateVaultPreviews", isDirectory: true)
    }

    private func purgeTemporaryPreviews() {
        try? fm.removeItem(at: previewRoot)
    }

    private func protectedWrite(_ data: Data, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }

    private func userError(_ message: String) -> NSError {
        NSError(domain: "PrivateVault", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
