import Foundation

struct VaultItem: Codable, Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var storedName: String
    var createdAt: Date
    var size: Int64
}

struct VaultManifest: Codable {
    var version: Int = 1
    var items: [VaultItem] = []
}

struct VaultHeader: Codable {
    var version: Int = 1
    var salt: Data
    var iterations: Int
    var wrappedVaultKey: Data
}
