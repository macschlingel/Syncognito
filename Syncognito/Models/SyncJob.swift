import Foundation

struct SyncJob: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var sourceURL: URL
    var targetURL: URL
    var syncIntervalInSeconds: TimeInterval = 15 * 60 // Default 15 minutes cooldown between syncs
    var fsEventDebounceInSeconds: TimeInterval = 60.0 // Default 60 seconds debounce for file changes
    var listenToChanges: Bool = true // User setting to toggle FSEvents monitoring
    var lastSyncDate: Date?
    var lastFSEventDate: Date? // Track when last file system event occurred
    var isSyncing: Bool = false
    var latestErrors: [String] = []

    // Progress tracking
    var filesProcessed: Int = 0
    var totalFiles: Int = 0
    var currentFile: String = ""
    
    // Security-Scoped Bookmarks to persist access across app restarts
    var sourceBookmarkData: Data?
    var targetBookmarkData: Data?

    static func == (lhs: SyncJob, rhs: SyncJob) -> Bool {
        lhs.id == rhs.id
    }
}
