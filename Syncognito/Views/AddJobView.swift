import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AddJobView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var syncManager: SyncManager

    @State private var sourceURL: URL?
    @State private var targetURL: URL?
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Add New Sync Job")
                .font(.title2)
                .fontWeight(.bold)

            HStack(spacing: 20) {
                FolderDropZone(
                    title: "Source",
                    url: $sourceURL,
                    onBrowse: { showFolderPicker(for: \.sourceURL) }
                )

                Image(systemName: "arrow.right")
                    .font(.title2)
                    .foregroundColor(.secondary)

                FolderDropZone(
                    title: "Target",
                    url: $targetURL,
                    onBrowse: { showFolderPicker(for: \.targetURL) }
                )
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create Job") {
                    createJob()
                }
                .disabled(sourceURL == nil || targetURL == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 600, height: 300)
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func showFolderPicker(for keyPath: ReferenceWritableKeyPath<AddJobView, URL?>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            self[keyPath: keyPath] = url
        }
    }

    private func createJob() {
        guard let source = sourceURL, let target = targetURL else { return }

        do {
            let sourceBookmark = try BookmarkManager.shared.createBookmark(for: source)
            let targetBookmark = try BookmarkManager.shared.createBookmark(for: target)

            let newJob = SyncJob(
                sourceURL: source,
                targetURL: target,
                sourceBookmarkData: sourceBookmark,
                targetBookmarkData: targetBookmark
            )

            syncManager.addJob(newJob)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

struct FolderDropZone: View {
    let title: String
    @Binding var url: URL?
    let onBrowse: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            if let url = url {
                VStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)

                    Text(url.lastPathComponent)
                        .font(.headline)
                        .lineLimit(2)

                    Text(url.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 2)
                )
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleDrop(providers: providers)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)

                    Text("Drop folder here")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button("Browse...") {
                        onBrowse()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                        .foregroundColor(.secondary.opacity(0.5))
                )
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
        .frame(height: 180)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            guard let data = item as? Data,
                  let path = String(data: data, encoding: .utf8),
                  let url = URL(string: path) else {
                return
            }

            DispatchQueue.main.async {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        self.url = url
                    }
                }
            }
        }
        return true
    }
}
