# PrivateVault for iPhone

A native SwiftUI starter for a local encrypted document vault.

## Security design
- The vault starts empty.
- A random 256-bit vault key encrypts imported files with AES-GCM (CryptoKit).
- The vault key is wrapped by a key derived from the master password.
- Password derivation uses PBKDF2-HMAC-SHA256 implemented with CommonCrypto, with a random salt and 600,000 iterations.
- The master password itself is never stored.
- Encrypted file blobs use iOS complete file protection.
- Decrypted previews are created only temporarily and removed when the preview closes.
- Face ID support is intentionally NOT enabled in this first security baseline. Add it only after the password-only flow is tested and reviewed.
- Backup export is a single encrypted `.pvault` package containing encrypted blobs and encrypted metadata.

## Important
This is a security-sensitive starter implementation, not a formally audited cryptographic product. Test it with non-sensitive files first and have the crypto/storage design reviewed before entrusting irreplaceable financial records to it.

## Build
Open the project files in Xcode on macOS, create an iOS App project named `PrivateVault`, then replace the generated Swift files with the files in `PrivateVault/`.

Recommended:
- SwiftUI
- iOS 17+
- Add `CommonCrypto` (available in the iOS SDK)
- Keep all actual vault data out of Git/GitHub.

The repository should contain source code only.
