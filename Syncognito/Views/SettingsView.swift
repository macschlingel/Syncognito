import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var syncManager: SyncManager
    @State private var showingAddJob = false

    var body: some View {
        VStack {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .frame(width: 64, height: 64)
                .cornerRadius(12)
                .padding(.top)

            Text("Syncognito Jobs")
                .font(.title2)
                .fontWeight(.bold)
            
            if syncManager.jobs.isEmpty {
                Text("No sync jobs configured.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(syncManager.jobs) { job in
                            JobRowView(syncManager: syncManager, jobId: job.id)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            HStack {
                Button(action: { showingAddJob = true }) {
                    Image(systemName: "plus")
                    Text("Add Job")
                }
                
                Spacer()
                
                Button("Sync All") {
                    syncManager.triggerAllActiveSyncs()
                }
                .disabled(syncManager.jobs.isEmpty)
            }
            .padding()
        }
        .padding()
        .frame(minWidth: 500, idealWidth: 600, maxHeight: 450)
        .sheet(isPresented: $showingAddJob) {
            AddJobView(syncManager: syncManager)
        }
    }
}
