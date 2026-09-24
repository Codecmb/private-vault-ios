import Foundation
import CryptoKit
import UniformTypeIdentifiers

@MainActor
final class VaultStore: ObservableObject {
    @Published var isConfigured = false
    @Published var isUnlocked = false
    @Published var items: [VaultItem] = []
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
        isConfigured = fm.fileExists(atPath: headerURL.path)
    }

    func create(password: String) throws {
        guard password.count >= 16 else {
            throw NSError(domain: "PrivateVault", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Use at least 16 characters."])
        }
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
        try saveManifest()
        isConfigured = true
        isUnlocked = true
    }

    func unlock(password: String) throws {
        let header = try JSONDecoder().decode(VaultHeader.self, from: Data(contentsOf: headerURL))
        let passwordKey = try CryptoService.deriveKey(password: password, salt: header.salt, iterations: header.iterations)
        let raw = try CryptoService.open(header.wrappedVaultKey, using: passwordKey)
        let key = SymmetricKey(data: raw)

        let encryptedManifest = try Data(contentsOf: manifestURL)
        let plainManifest = try CryptoService.open(encryptedManifest, using: key)
        let manifest = try JSONDecoder().decode(VaultManifest.self, from: plainManifest)

        vaultKey = key
        items = manifest.items
        isUnlocked = true
    }

    func lock() {
        vaultKey = nil
        items = []
        isUnlocked = false
    }

    func importFiles(_ urls: [URL]) async {
        guard let key = vaultKey else { return }
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                let encrypted = try CryptoService.seal(data, using: key)
                let storedName = UUID().uuidString + ".blob"
                let target = blobsURL.appendingPathComponent(storedName)
                try protectedWrite(encrypted, to: target)

                let item = VaultItem(
                    id: UUID(),
                    displayName: url.lastPathComponent,
                    storedName: storedName,
                    createdAt: Date(),
                    size: Int64(data.count)
                )
                items.append(item)
                try saveManifest()
            } catch {
                errorMessage = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    func decryptedTemporaryURL(for item: VaultItem) throws -> URL {
        guard let key = vaultKey else { throw VaultCryptoError.invalidPassword }
        let encrypted = try Data(contentsOf: blobsURL.appendingPathComponent(item.storedName))
        let clear = try CryptoService.open(encrypted, using: key)

        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let out = tempDir.appendingPathComponent(item.displayName)
        try clear.write(to: out, options: [.atomic, .completeFileProtection])
        return out
    }

    func delete(_ item: VaultItem) throws {
        try? fm.removeItem(at: blobsURL.appendingPathComponent(item.storedName))
        items.removeAll { $0.id == item.id }
        try saveManifest()
    }

    private func saveManifest() throws {
        guard let key = vaultKey else { return }
        let plain = try JSONEncoder().encode(VaultManifest(items: items))
        let encrypted = try CryptoService.seal(plain, using: key)
        try protectedWrite(encrypted, to: manifestURL)
    }

    private func protectedWrite(_ data: Data, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }
}
