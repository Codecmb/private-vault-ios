import SwiftUI
import UIKit

@main
struct PrivateVaultApp: App {
    @StateObject private var vault = VaultStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vault)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    vault.lock()
                }
        }
    }
}
