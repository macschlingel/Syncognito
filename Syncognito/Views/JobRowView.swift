import SwiftUI

struct JobRowView: View {
    @ObservedObject var syncManager: SyncManager
    var jobId: UUID

    // Look up job dynamically from syncManager
    private var job: SyncJob? {
        syncManager.jobs.first(where: { $0.id == jobId })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let job = job {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(job.sourceURL.lastPathComponent)
                            .font(.headline)
                            .help(job.sourceURL.path)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(job.targetURL.lastPathComponent)
                            .font(.headline)
                            .help(job.targetURL.path)
                    }
                }

                // Show progress bar when syncing
                if job.isSyncing && job.totalFiles > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: Double(job.filesProcessed), total: Double(job.totalFiles))
                            .progressViewStyle(.linear)
                        Text("\(job.filesProcessed) / \(job.totalFiles)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if !job.currentFile.isEmpty {
                            Text(job.currentFile)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                HStack(spacing: 12) {
                    Toggle("Sync on file changes", isOn: Binding(
                        get: { job.listenToChanges },
                        set: { newValue in
                            syncManager.updateJobListenToChanges(id: job.id, listen: newValue)
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .fixedSize()

                    Divider()
                        .frame(height: 16)

                    HStack(spacing: 4) {
                        Text(job.listenToChanges ? "Min wait after sync:" : "Sync interval:")
                            .fixedSize()
                            .help(job.listenToChanges ? "Minimum time to wait after a successful sync before triggering another" : "How often to automatically sync")
                        Picker("", selection: Binding(
                            get: { job.syncIntervalInSeconds },
                            set: { newValue in
                                syncManager.updateJobInterval(id: job.id, newInterval: newValue)
                            }
                        )) {
                            Text("1 Min").tag(1 * 60.0)
                            Text("5 Mins").tag(5 * 60.0)
                            Text("15 Mins").tag(15 * 60.0)
                            Text("30 Mins").tag(30 * 60.0)
                            Text("60 Mins").tag(60 * 60.0)
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }

                    Spacer()

                    if let lastSync = job.lastSyncDate {
                        Text("Last: \(lastSync, style: .time)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Pending Sync")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button(action: {
                        syncManager.triggerManualSync(for: job.id)
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .imageScale(.large)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .help("Sync Now")

                    Button(action: {
                        syncManager.removeJob(with: job.id)
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .imageScale(.large)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .padding(.leading, 8)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
