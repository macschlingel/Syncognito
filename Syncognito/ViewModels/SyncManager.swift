import Foundation
import SwiftUI
import Combine

@MainActor
class SyncManager: ObservableObject {
    @Published var jobs: [SyncJob] = []

    private let defaults = UserDefaults.standard
    private let jobsKey = "syncognito_jobs"

    private var monitors: [UUID: FolderMonitor] = [:]
    private var syncWorkItems: [UUID: DispatchWorkItem] = [:]
    private var activeAccessURLs: [UUID: URL] = [:]
    private var periodicSyncTimers: [UUID: Timer] = [:]

    /// Returns true if any job is currently syncing
    var isAnySyncing: Bool {
        jobs.contains(where: { $0.isSyncing })
    }
    
    init() {
        loadJobs()
        setupMonitors()
    }
    
    deinit {
        // Best effort to clean up security-scoped access
        for url in activeAccessURLs.values {
            BookmarkManager.shared.stopAccessing(url: url)
        }
    }
    
    func addJob(_ job: SyncJob) {
        jobs.append(job)
        saveJobs()

        // Initial sync
        executeSync(for: job.id)

        // Set up FSEvents or periodic timer based on listenToChanges
        if job.listenToChanges {
            startMonitoring(for: job)
        } else {
            startPeriodicSync(for: job)
        }
    }
    
    func removeJob(with id: UUID) {
        if let job = jobs.first(where: { $0.id == id }) {
            stopMonitoring(for: job)
            stopPeriodicSync(for: job)
        }
        jobs.removeAll(where: { $0.id == id })
        saveJobs()
    }
    
    func updateJobInterval(id: UUID, newInterval: TimeInterval) {
        if let index = jobs.firstIndex(where: { $0.id == id }) {
            jobs[index].syncIntervalInSeconds = newInterval
            saveJobs()
        }
    }
    
    func updateJobListenToChanges(id: UUID, listen: Bool) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        let job = jobs[index]

        jobs[index].listenToChanges = listen
        saveJobs()

        if listen {
            // Switch to FSEvents: stop periodic timer, start monitoring
            stopPeriodicSync(for: job)
            startMonitoring(for: job)
        } else {
            // Switch to periodic: stop monitoring, start periodic timer
            stopMonitoring(for: job)
            startPeriodicSync(for: job)
        }
    }
    
    func triggerManualSync(for id: UUID) {
        executeSync(for: id)
    }
    
    func triggerAllActiveSyncs() {
        print("Sync All triggered for \(jobs.count) jobs")
        for job in jobs {
            print("Triggering sync for job: \(job.sourceURL.lastPathComponent) -> \(job.targetURL.lastPathComponent)")
            executeSync(for: job.id)
        }
    }
    
    private func loadJobs() {
        if let data = defaults.data(forKey: jobsKey),
           let decoded = try? JSONDecoder().decode([SyncJob].self, from: data) {
            self.jobs = decoded
        }
    }
    
    private func saveJobs() {
        if let data = try? JSONEncoder().encode(jobs) {
            defaults.set(data, forKey: jobsKey)
        }
    }
    
    private func setupMonitors() {
        for job in jobs {
            if job.listenToChanges {
                startMonitoring(for: job)
            } else {
                startPeriodicSync(for: job)
            }
        }
    }
    
    private func startMonitoring(for job: SyncJob) {
        // Only start if not already monitored to prevent duplicates
        guard monitors[job.id] == nil else { return }
        
        let monitor = FolderMonitor()
        
        monitor.folderDidChange = { [weak self] in
            Task { @MainActor in
                self?.handleFolderChange(for: job.id)
            }
        }
        
        var sourceURL = job.sourceURL
        if let bookmarkData = job.sourceBookmarkData {
             if let (url, _) = try? BookmarkManager.shared.resolveBookmark(bookmarkData) {
                 sourceURL = url
                 if BookmarkManager.shared.startAccessing(url: sourceURL) {
                     activeAccessURLs[job.id] = sourceURL
                 }
             }
        }
        
        monitor.startMonitoring(url: sourceURL)
        monitors[job.id] = monitor
    }
    
    private func stopMonitoring(for job: SyncJob) {
        monitors[job.id]?.stopMonitoring()
        monitors.removeValue(forKey: job.id)
        syncWorkItems[job.id]?.cancel()
        syncWorkItems.removeValue(forKey: job.id)

        if let url = activeAccessURLs[job.id] {
            BookmarkManager.shared.stopAccessing(url: url)
            activeAccessURLs.removeValue(forKey: job.id)
        }
    }

    private func startPeriodicSync(for job: SyncJob) {
        // Only start if not already running
        guard periodicSyncTimers[job.id] == nil else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: job.syncIntervalInSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.executeSync(for: job.id)
            }
        }

        periodicSyncTimers[job.id] = timer
    }

    private func stopPeriodicSync(for job: SyncJob) {
        periodicSyncTimers[job.id]?.invalidate()
        periodicSyncTimers.removeValue(forKey: job.id)
    }
    
    private func handleFolderChange(for jobId: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        let job = jobs[index]

        // Record when this FSEvent occurred
        jobs[index].lastFSEventDate = Date()

        // Check if we should sync immediately (last sync was more than cooldown period ago)
        let timeSinceLastSync: TimeInterval
        if let lastSync = job.lastSyncDate {
            timeSinceLastSync = Date().timeIntervalSince(lastSync)
        } else {
            timeSinceLastSync = .infinity // Never synced, so treat as very long time ago
        }

        // Cancel any previously scheduled sync
        syncWorkItems[jobId]?.cancel()

        if timeSinceLastSync > job.syncIntervalInSeconds {
            // Last sync was > 15 minutes ago, trigger immediately
            executeSync(for: jobId)
        } else {
            // Last sync was recent, wait for debounce period after last FSEvent
            let workItem = DispatchWorkItem { [weak self] in
                self?.executeSync(for: jobId)
            }
            syncWorkItems[jobId] = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + job.fsEventDebounceInSeconds, execute: workItem)
        }
    }
    
    private func executeSync(for jobId: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobId }) else {
            print("Job not found: \(jobId)")
            return
        }

        print("Starting sync for job: \(jobs[index].sourceURL.path) -> \(jobs[index].targetURL.path)")

        // Mark as syncing
        jobs[index].isSyncing = true
        jobs[index].latestErrors = []
        jobs[index].filesProcessed = 0
        jobs[index].totalFiles = 0
        jobs[index].currentFile = ""
        let job = jobs[index]

        SyncEngine.shared.sync(job: job, progress: { [weak self] filesProcessed, totalFiles, currentFile in
            print("Progress: \(filesProcessed)/\(totalFiles) - \(currentFile)")
            Task { @MainActor in
                guard let self = self, let idx = self.jobs.firstIndex(where: { $0.id == jobId }) else { return }
                self.jobs[idx].filesProcessed = filesProcessed
                self.jobs[idx].totalFiles = totalFiles
                self.jobs[idx].currentFile = currentFile
            }
        }, completion: { [weak self] success, error in
            print("Sync completed - Success: \(success), Error: \(error?.localizedDescription ?? "none")")
            Task { @MainActor in
                guard let self = self else { return }

                if let idx = self.jobs.firstIndex(where: { $0.id == jobId }) {
                    self.jobs[idx].isSyncing = false

                    if success {
                        self.jobs[idx].lastSyncDate = Date()
                        self.jobs[idx].latestErrors = []
                        self.jobs[idx].filesProcessed = 0
                        self.jobs[idx].totalFiles = 0
                        self.jobs[idx].currentFile = ""
                        self.saveJobs()
                    } else if let error = error {
                        self.jobs[idx].latestErrors = [error.localizedDescription]
                    }
                }
            }
        })
    }
}
