import Foundation

class BookmarkManager {
    static let shared = BookmarkManager()

    private init() {}

    /// Creates a security-scoped bookmark for the given URL.
    /// Used when a user selects a folder via NSOpenPanel.
    func createBookmark(for url: URL) throws -> Data {
        // Create the bookmark data allowing persistent access
        return try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Resolves a security-scoped bookmark back to an accessible URL.
    func resolveBookmark(_ bookmarkData: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }

    /// Helper to start accessing a security scoped resource.
    /// Caller MUST ensure `stopAccessingSecurityScopedResource()` is called later.
    func startAccessing(url: URL) -> Bool {
        return url.startAccessingSecurityScopedResource()
    }

    /// Helper to stop accessing a security scoped resource.
    func stopAccessing(url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
