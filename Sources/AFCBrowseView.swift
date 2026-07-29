//
//  AFCBrowseView.swift
//  AppFileManager
//
//  Browse device files via standard AFC (same as SparseBox).
//  This gives access to /var/mobile/Media and other AFC-accessible paths.
//

import SwiftUI

struct AFCBrowseView: View {
    @State private var afcPath: String
    @State private var items: [DirectoryEntry] = []
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage: String?
    
    struct DirectoryEntry: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let isDirectory: Bool
    }
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Cannot access this path")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(items) { entry in
                        NavigationLink {
                            if entry.isDirectory {
                                AFCBrowseView(afcPath: currentAfcPath(for: entry.name))
                            } else {
                                AFCFilePreviewView(
                                    path: currentAfcPath(for: entry.name),
                                    fileName: entry.name
                                )
                            }
                        } label: {
                            HStack {
                                Image(systemName: entry.isDirectory ? "folder.fill" : "doc.text")
                                    .foregroundColor(entry.isDirectory ? .blue : .orange)
                                    .frame(width: 24)
                                Text(entry.name)
                                    .font(.body)
                            }
                            .padding(.vertical, 2)
                        }
                        .contextMenu {
                            if !entry.isDirectory {
                                Button {
                                    pullAfcFile(entry: entry)
                                } label: {
                                    Label("Download to Device", systemImage: "arrow.down.circle")
                                }
                            }
                            
                            Button(role: .destructive) {
                                deleteAfcEntry(entry: entry)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(
            afcPath == "/" ? "Media Root" :
            (afcPath as NSString).lastPathComponent
        )
        .alert("Error", isPresented: $showError) {
            Button("OK") { showError = false }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .onAppear {
            loadDirectory()
        }
    }
    
    init() {
        _afcPath = State(initialValue: "/")
    }
    
    init(afcPath: String) {
        _afcPath = State(initialValue: afcPath)
    }
    
    private func currentAfcPath(for name: String) -> String {
        if afcPath == "/" {
            return "/" + name
        }
        return afcPath + "/" + name
    }
    
    private func loadDirectory() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let entries = (try? JITEnableContext.shared.afcListDir(self.afcPath)) ?? []

            var results: [DirectoryEntry] = []
            if !entries.isEmpty {
                let filtered = entries.filter { $0 != "." && $0 != ".." }
                for entry in filtered {
                    let fullPath = self.currentAfcPath(for: entry)
                    let isDir = JITEnableContext.shared.afcIsPathDirectory(fullPath)
                    results.append(DirectoryEntry(name: entry, isDirectory: isDir))
                }
            }
            
            // Sort: directories first, then files
            results.sort { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name < b.name
            }
            
            DispatchQueue.main.async {
                self.items = results
                self.isLoading = false
            }
        }
    }
    
    private func pullAfcFile(entry: DirectoryEntry) {
        let fullPath = currentAfcPath(for: entry.name)
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let localPath = docDir.appendingPathComponent(entry.name).path
        
        DispatchQueue.global(qos: .userInitiated).async {
            let success = (try? JITEnableContext.shared.afcPullFile(fullPath, toLocalPath: localPath)) ?? false

            DispatchQueue.main.async {
                if !success {
                    self.errorMessage = "Failed to download"
                    self.showError = true
                } else {
                    let alert = UIAlertController(
                        title: "Downloaded",
                        message: "\(entry.name) saved to app Documents.",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootVC = windowScene.windows.first?.rootViewController {
                        rootVC.present(alert, animated: true)
                    }
                }
            }
        }
    }
    
    private func deleteAfcEntry(entry: DirectoryEntry) {
        let fullPath = currentAfcPath(for: entry.name)
        let alert = UIAlertController(
            title: "Delete?",
            message: "Are you sure you want to delete \(entry.name)?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            DispatchQueue.global(qos: .userInitiated).async {
                let success = (try? JITEnableContext.shared.afcDelete(fullPath)) ?? false

                DispatchQueue.main.async {
                    if success {
                        self.loadDirectory()
                    } else {
                        self.errorMessage = "Failed to delete"
                        self.showError = true
                    }
                }
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(alert, animated: true)
        }
    }
}

// Simple file preview for AFC files
struct AFCFilePreviewView: View {
    let path: String
    let fileName: String
    
    @State private var content: String?
    @State private var isImage = false
    @State private var imageData: Data?
    
    var body: some View {
        Group {
            if isImage, let imageData = imageData, let uiImage = UIImage(data: imageData) {
                ScrollView {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .padding()
                }
            } else if let content = content {
                ScrollView {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(fileName)
                        .font(.title3)
                    Text("File preview not available.\nDownload to view.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(fileName)
        .onAppear {
            loadPreview()
        }
    }
    
    private func loadPreview() {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let imageExts = ["jpg", "jpeg", "png", "gif", "heic", "webp"]
        
        if imageExts.contains(ext) {
            isImage = true
            // Download image data for preview
            let tempPath = FileManager.default.temporaryDirectory.appendingPathComponent(fileName).path
            let success = (try? JITEnableContext.shared.afcPullFile(path, toLocalPath: tempPath)) ?? false
            if success {
                imageData = FileManager.default.contents(atPath: tempPath)
                try? FileManager.default.removeItem(atPath: tempPath)
            }
        } else {
            // Try to load as text for plist, json, xml, txt, log
            let textExts = ["plist", "json", "xml", "txt", "log", "md", "cfg", "conf", "ini"]
            if textExts.contains(ext) {
                let tempPath = FileManager.default.temporaryDirectory.appendingPathComponent(fileName).path
                let success = (try? JITEnableContext.shared.afcPullFile(path, toLocalPath: tempPath)) ?? false
                if success {
                    content = try? String(contentsOfFile: tempPath, encoding: .utf8)
                    try? FileManager.default.removeItem(atPath: tempPath)
                }
            }
        }
    }
}
