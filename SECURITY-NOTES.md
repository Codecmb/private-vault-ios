# Security notes

Before production use:
1. Have the cryptographic design and implementation independently reviewed.
2. Add authenticated encrypted backup/restore with versioning before storing important data.
3. Add password-change support by re-wrapping the random vault key; do not re-encrypt every document unnecessarily.
4. Add optional Face ID by protecting a vault-unlock secret with Keychain access control requiring biometryCurrentSet.
5. Never store the master password.
6. Never log filenames, plaintext, passwords, keys, or decrypted contents.
7. Remove temporary decrypted previews on lock/background and at startup.
8. Add tests for corrupt ciphertext, wrong passwords, interrupted writes, duplicate filenames, very large files, low storage, and backup recovery.
9. Consider memory-copy minimization for sensitive key material. Swift/Data cannot guarantee perfect zeroization.
10. Keep source code separate from user vault data.
