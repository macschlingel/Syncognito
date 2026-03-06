import Foundation
import CoreServices

class FolderMonitor {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.syncognito.foldermonitor", attributes: .concurrent)
    
    /// Closure called when a file or directory change is detected.
    var folderDidChange: (() -> Void)?
    
    func startMonitoring(url: URL) {
        let pathsToWatch = [url.path] as CFArray
        
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        var streamContext = FSEventStreamContext(
            version: 0,
            info: context,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        let callback: FSEventStreamCallback = { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
            guard let clientCallBackInfo = clientCallBackInfo else { return }
            let monitor = Unmanaged<FolderMonitor>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
            // Dispatch back to main queue for handling
            DispatchQueue.main.async {
                monitor.folderDidChange?()
            }
        }
        
        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &streamContext,
            pathsToWatch,
            FSEventsGetCurrentEventId(),
            1.0, // Throttling at the FSEvents level
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )
        
        if let stream = stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }
    
    func stopMonitoring() {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }
}
