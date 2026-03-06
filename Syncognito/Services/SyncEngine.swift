import Foundation

class SyncEngine {
    static let shared = SyncEngine()
    private let fileManager = FileManager.default

    private init() {}

    /// Performs the synchronization for a given job.
    /// - Parameters:
    ///   - job: The SyncJob configuration to process.
    ///   - progress: Closure called during sync to report progress (filesProcessed, totalFiles, currentFile).
    ///   - completion: Closure called when sync is done. `success` indicates if the target was reachable and synced, or silently skipped.
    func sync(job: SyncJob, progress: @escaping (Int, Int, String) -> Void, completion: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        print("SyncEngine.sync() called for: \(job.sourceURL.lastPathComponent) -> \(job.targetURL.lastPathComponent)")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var sourceURL = job.sourceURL
                var targetURL = job.targetURL
                var startedSource = false
                var startedTarget = false

                // 1. Resolve Bookmarks and gain access permissions
                if let srcData = job.sourceBookmarkData {
                    print("Resolving source bookmark...")
                    let (url, _) = try BookmarkManager.shared.resolveBookmark(srcData)
                    sourceURL = url
                    print("Source bookmark resolved: \(sourceURL.path)")
                    startedSource = BookmarkManager.shared.startAccessing(url: sourceURL)
                    print("Source access started: \(startedSource)")
                }

                if let tgtData = job.targetBookmarkData {
                    print("Resolving target bookmark...")
                    let (url, _) = try BookmarkManager.shared.resolveBookmark(tgtData)
                    targetURL = url
                    print("Target bookmark resolved: \(targetURL.path)")
                    startedTarget = BookmarkManager.shared.startAccessing(url: targetURL)
                    print("Target access started: \(startedTarget)")
                }

                // Make sure to stop accessing after sync finishes
                defer {
                    if startedSource { BookmarkManager.shared.stopAccessing(url: sourceURL) }
                    if startedTarget { BookmarkManager.shared.stopAccessing(url: targetURL) }
                }

                // 2. Verify target is reachable (e.g. NAS might be disconnected)
                print("Checking if target is reachable: \(targetURL.path)")
                guard try self.isReachable(url: targetURL) else {
                    // Target unreachable, abort silently as per requirements
                    print("Target is NOT reachable - aborting sync")
                    DispatchQueue.main.async { completion(false, nil) }
                    return
                }
                print("Target is reachable")

                // 3. Perform One-Way Incremental Sync
                try self.performOneWaySync(source: sourceURL, target: targetURL, progress: progress)

                DispatchQueue.main.async {
                    completion(true, nil)
                }
            } catch {
                print("Sync error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(false, error)
                }
            }
        }
    }

    private func isReachable(url: URL) throws -> Bool {
        return try url.checkResourceIsReachable()
    }

    private func performOneWaySync(source: URL, target: URL, progress: @escaping (Int, Int, String) -> Void) throws {
        // Count total files first
        let totalCount = try countFiles(at: source)

        // Enumerate through all contents of the source directory
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]

        let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: options
        )

        // Ensure path normalizations for relative path extractions
        let sourcePath = source.path + (source.path.hasSuffix("/") ? "" : "/")

        var filesProcessed = 0

        while let sourceItemURL = enumerator?.nextObject() as? URL {
            do {
                guard sourceItemURL.path.hasPrefix(sourcePath) else { continue }
                let relativePath = String(sourceItemURL.path.dropFirst(sourcePath.count))
                let targetItemURL = target.appendingPathComponent(relativePath)

                let resourceValues = try sourceItemURL.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .isSymbolicLinkKey])

                // Skip symlinks to prevent path duplication issues
                let isSymlink = resourceValues.isSymbolicLink ?? false
                if isSymlink {
                    continue
                }

                let isDirectory = resourceValues.isDirectory ?? false

                if isDirectory {
                    // If it's a directory and doesn't exist at the target, create it
                    if !fileManager.fileExists(atPath: targetItemURL.path) {
                        try fileManager.createDirectory(at: targetItemURL, withIntermediateDirectories: true, attributes: nil)
                    }
                } else {
                    let fileName = sourceItemURL.lastPathComponent
                    filesProcessed += 1
                    progress(filesProcessed, totalCount, fileName)

                    let sourceDate = resourceValues.contentModificationDate ?? Date.distantPast

                    if fileManager.fileExists(atPath: targetItemURL.path) {
                        // Check modification dates for existing files
                        let targetAttributes = try fileManager.attributesOfItem(atPath: targetItemURL.path)
                        let targetDate = targetAttributes[.modificationDate] as? Date ?? Date.distantPast

                        // Incrementally sync if source file is newer
                        if sourceDate > targetDate {
                            try safelyRemoveItem(at: targetItemURL)
                            try fileManager.copyItem(at: sourceItemURL, to: targetItemURL)
                        }
                    } else {
                        // File doesn't exist, guarantee target directory exists then copy
                        let parentDir = targetItemURL.deletingLastPathComponent()
                        if !fileManager.fileExists(atPath: parentDir.path) {
                            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
                        }

                        // Safely remove just in case to prevent "Item already exists" (e.g. symlinks/hidden conflicts)
                        try? safelyRemoveItem(at: targetItemURL)
                        try fileManager.copyItem(at: sourceItemURL, to: targetItemURL)
                    }
                }
            } catch {
                print("Failed to sync item at \(sourceItemURL.path): \(error.localizedDescription)")
                // Continue to the next item instead of aborting the whole sync job
            }
        }
    }

    private func countFiles(at url: URL) throws -> Int {
        print("Counting files at: \(url.path)")
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: options
        )

        var count = 0
        while let itemURL = enumerator?.nextObject() as? URL {
            let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])

            // Skip symlinks and directories
            let isSymlink = resourceValues.isSymbolicLink ?? false
            let isDirectory = resourceValues.isDirectory ?? false

            if !isSymlink && !isDirectory {
                count += 1
            }
        }
        print("Total files to sync: \(count)")
        return count
    }
    
    private func safelyRemoveItem(at url: URL) throws {
        // Attempt to remove the item normally first
        do {
            try fileManager.removeItem(at: url)
        } catch {
            // If it fails, try to aggressively alter permissions and try again
            var attributes = [FileAttributeKey: Any]()
            attributes[.immutable] = false // Unlock if locked
            attributes[.posixPermissions] = NSNumber(value: 0o777) // Add write permissions
            try? fileManager.setAttributes(attributes, ofItemAtPath: url.path)
            
            // Retry removal
            try fileManager.removeItem(at: url)
        }
    }
}
