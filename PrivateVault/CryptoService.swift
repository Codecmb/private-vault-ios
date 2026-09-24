import Foundation
import CryptoKit
import CommonCrypto
import Security

enum VaultCryptoError: Error {
    case invalidPassword
    case malformedCiphertext
    case derivationFailed
}

enum CryptoService {
    static let iterations = 600_000
    static let saltBytes = 32
    static let keyBytes = 32

    static func randomData(count: Int) -> Data {
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!)
        }
        precondition(result == errSecSuccess)
        return data
    }

    static func deriveKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let passwordData = Data(password.utf8)
        var output = Data(count: keyBytes)

        let status: Int32 = output.withUnsafeMutableBytes { outBuf in
            salt.withUnsafeBytes { saltBuf in
                passwordData.withUnsafeBytes { passBuf in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passBuf.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBuf.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        outBuf.bindMemory(to: UInt8.self).baseAddress,
                        keyBytes
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw VaultCryptoError.derivationFailed }
        return SymmetricKey(data: output)
    }

    static func seal(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else { throw VaultCryptoError.malformedCiphertext }
        return combined
    }

    static func open(_ ciphertext: Data, using key: SymmetricKey) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: ciphertext)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw VaultCryptoError.invalidPassword
        }
    }
}
