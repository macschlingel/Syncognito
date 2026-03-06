import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct SyncognitoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var syncManager = SyncManager()


    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(syncManager)
        }

        MenuBarExtra(content: {
            VStack {
                if syncManager.jobs.isEmpty {
                    Text("No Sync Jobs")
                } else {
                    let lastSyncs = syncManager.jobs.compactMap { $0.lastSyncDate }.sorted(by: >)
                    if let latest = lastSyncs.first {
                        Text("Last Sync: \(latest, style: .time)")
                    } else {
                        Text("Status: Pending")
                    }
                }

                Divider()

                Button("Sync Now") {
                    syncManager.triggerAllActiveSyncs()
                }
                .disabled(syncManager.jobs.isEmpty)

                Button("Check for Updates...") {
                    NSApp.sendAction(Selector(("checkForUpdates:")), to: nil, from: nil)
                }

                SettingsLink {
                    Text("Settings...")
                }

                Divider()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }, label: {
            if syncManager.isAnySyncing {
                Label("Syncing", systemImage: "arrow.triangle.2.circlepath")
                    .symbolEffect(.rotate)
            } else {
                Label("Syncognito", systemImage: "arrow.triangle.2.circlepath")
            }
        })
    }
}
