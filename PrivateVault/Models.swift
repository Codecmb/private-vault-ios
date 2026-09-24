import Foundation

struct VaultFolder: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
}

struct VaultItem: Codable, Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var storedName: String
    var createdAt: Date
    var size: Int64
    var folderID: UUID?
}

struct VaultManifest: Codable {
    var version: Int = 2
    var folders: [VaultFolder] = []
    var items: [VaultItem] = []
}

struct VaultHeader: Codable {
    var version: Int = 1
    var salt: Data
    var iterations: Int
    var wrappedVaultKey: Data
}

struct BackupBlob: Codable {
    var storedName: String
    var ciphertext: Data
}

struct VaultBackup: Codable {
    var version: Int = 1
    var header: VaultHeader
    var encryptedManifest: Data
    var blobs: [BackupBlob]
}
