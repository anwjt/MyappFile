//
//  AppSandboxBrowserView.swift
//  AppFileManager
//
//  Main file browser view for app sandbox via HouseArrest + AFC protocol.
//  Supports: browse, pull, push, delete, create directory.
//

import SwiftUI
import UniformTypeIdentifiers

struct AppSandboxBrowserView: View {
    let bundleId: String
    let appName: String
    let command: HouseArrestCommand
    
    @State private var currentPath: String = "/"
    @State private var items: [DirectoryEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showPushPicker = false
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var afcClient: AfcClientHandle?
    @State private var showFileActionSheet = false
    @State private var selectedFileEntry: DirectoryEntry?
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var selectedRenameEntry: DirectoryEntry?
    
    struct DirectoryEntry: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let isDirectory: Bool
        let size: UInt64
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Info bar
            HStack {
                Text(appName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(command == .vendContainer ? "Full Container" : "Documents")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            
            // Path breadcrumb
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    Button {
                        navigateToPath("/")
                    } label: {
                        Text("Root")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    ForEach(getBreadcrumbComponents(), id: \.self) { component in
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        let idx = getBreadcrumbComponents().firstIndex(of: component)!
                        let pathSoFar = "/" + getBreadcrumbComponents().prefix(idx + 1).joined(separator: "/")
                        Button {
                            navigateToPath(pathSoFar)
                        } label: {
                            Text(component)
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            
            // File list
            List {
                ForEach(items) { entry in
                    if entry.name != "." && entry.name != ".." {
                        HStack {
                            Image(systemName: entry.isDirectory ? "folder.fill" : fileIcon(for: entry.name))
                                .foregroundColor(entry.isDirectory ? .blue : .orange)
                                .frame(width: 24)
                            
                            Text(entry.name)
                                .font(.body)
                            
                            Spacer()
                            
                            if !entry.isDirectory && entry.size > 0 {
                                Text(formatSize(entry.size))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if entry.isDirectory {
                                navigateToPath(currentPath + "/" + entry.name)
                            } else {
                                selectedFileEntry = entry
                                showFileActionSheet = true
                            }
                        }
                        .contextMenu {
                            if entry.isDirectory {
                                Button {
                                    navigateToPath(currentPath + "/" + entry.name)
                                } label: {
                                    Label("Open", systemImage: "folder")
                                }
                            } else {
                                Button {
                                    pullFile(entry: entry)
                                } label: {
                                    Label("Download to Device", systemImage: "arrow.down.circle")
                                }
                            }
                            
                            Button {
                                selectedRenameEntry = entry
                                renameText = entry.name
                                showRenameAlert = true
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            
                            Button(role: .destructive) {
                                deleteEntry(entry: entry)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground).opacity(0.8))
                }
            }
        }
        .navigationTitle(navigationTitleText)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showPushPicker = true
                    } label: {
                        Label("Push File...", systemImage: "arrow.up.circle")
                    }
                    
                    Button {
                        showNewFolderAlert = true
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    
                    Button {
                        loadDirectory()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    
                    Divider()
                    
                    Button {
                        connectAfcClient()
                    } label: {
                        Label("Reconnect", systemImage: "arrow.clockwise.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            
            ToolbarItem(placement: .navigationBarLeading) {
                if currentPath != "/" {
                    Button {
                        navigateToParent()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
        }
        .onAppear {
            connectAfcClient()
        }
        .fileImporter(
            isPresented: $showPushPicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .alert("New Folder", isPresented: $showNewFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Create", action: createFolder)
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename", isPresented: $showRenameAlert) {
            TextField("New name", text: $renameText)
            Button("Rename", action: renameEntry)
            Button("Cancel", role: .cancel) {}
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { showError = false }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .actionSheet(isPresented: $showFileActionSheet) {
            ActionSheet(
                title: Text(selectedFileEntry?.name ?? "File"),
                message: Text(formatSize(selectedFileEntry?.size ?? 0)),
                buttons: [
                    .default(Text("Download to Device")) {
                        if let entry = selectedFileEntry {
                            pullFile(entry: entry)
                        }
                    },
                    .default(Text("Rename")) {
                        if let entry = selectedFileEntry {
                            selectedRenameEntry = entry
                            renameText = entry.name
                            showRenameAlert = true
                        }
                    },
                    .destructive(Text("Delete")) {
                        if let entry = selectedFileEntry {
                            deleteEntry(entry: entry)
                        }
                    },
                    .cancel()
                ]
            )
        }
    }
    
    // MARK: - Navigation
    
    var navigationTitleText: String {
        if currentPath == "/" {
            return appName
        } else {
            return (currentPath as NSString).lastPathComponent
        }
    }
    
    func navigateToPath(_ path: String) {
        currentPath = path
        loadDirectory()
    }
    
    func navigateToParent() {
        let components = currentPath.components(separatedBy: "/").filter { !$0.isEmpty }
        if components.count > 1 {
            navigateToPath("/" + components.dropLast().joined(separator: "/"))
        } else {
            navigateToPath("/")
        }
    }
    
    func getBreadcrumbComponents() -> [String] {
        return currentPath.components(separatedBy: "/").filter { !$0.isEmpty }
    }
    
    // MARK: - AFC Client
    
    func connectAfcClient() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let client = try? JITEnableContext.shared.houseArrestConnect(forBundleId: bundleId, command: command)

            DispatchQueue.main.async {
                if let client = client {
                    self.afcClient = client
                    self.isLoading = false
                    self.loadDirectory()
                } else {
                    self.isLoading = false
                    self.errorMessage = "Failed to connect to app sandbox"
                    self.showError = true
                }
            }
        }
    }
    
    // MARK: - Directory Loading
    
    func loadDirectory() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            guard let client = self.afcClient else {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Not connected. Please reconnect."
                    self.showError = true
                }
                return
            }
            
            var error: NSError?
            let entries = (try? JITEnableContext.shared.houseArrestListDir(client, path: self.currentPath)) ?? []
            
            var results: [DirectoryEntry] = []
            
            if let entries = entries {
                // Get file info for all entries
                var entryInfos: [(String, Bool, UInt64)] = []
                for entry in entries {
                    let fullPath = self.currentPath == "/" ? "/\(entry)" : self.currentPath + "/" + entry
                    var size: UInt64 = 0
                    var isDir = false
                    _ = try? JITEnableContext.shared.houseArrestGetFileInfo(client, path: fullPath, size: &size, isDir: &isDir, error: nil)
                    entryInfos.append((entry, isDir, size))
                }
                
                // Sort: directories first, then files; alphabetically within each group
                let sorted = entryInfos.sorted { a, b in
                    if a.1 != b.1 { return a.1 }  // directories first
                    return a.0 < b.0              // alphabetical
                }
                
                for (name, isDir, size) in sorted {
                    results.append(DirectoryEntry(name: name, isDirectory: isDir, size: size))
                }
            }
            
            DispatchQueue.main.async {
                self.items = results
                self.isLoading = false
                if results.isEmpty {
                    self.errorMessage = "Failed to list directory or directory is empty"
                    self.showError = true
                }
            }
        }
    }
    
    // MARK: - File Operations
    
    func pullFile(entry: DirectoryEntry) {
        let fullPath = currentPath + "/" + entry.name
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let localPath = docDir.appendingPathComponent(entry.name).path
        
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            guard let client = self.afcClient else { return }
            
            let success = (try? JITEnableContext.shared.houseArrestPullFile(
                client,
                fromDevicePath: fullPath,
                toLocalPath: localPath
            )) ?? false
            
            DispatchQueue.main.async {
                self.isLoading = false
                if success {
                    // Show success - open in Files app
                    let alert = UIAlertController(
                        title: "Downloaded",
                        message: "\(entry.name) saved to app Documents.\nYou can access it via the Files app.",
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootVC = windowScene.windows.first?.rootViewController {
                        rootVC.present(alert, animated: true)
                    }
                } else {
                    self.errorMessage = error?.localizedDescription ?? "Failed to download file"
                    self.showError = true
                }
            }
        }
    }
    
    func deleteEntry(entry: DirectoryEntry) {
        let fullPath = currentPath + "/" + entry.name
        let alert = UIAlertController(
            title: "Delete?",
            message: "Are you sure you want to delete \(entry.name)? This cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let client = self.afcClient else { return }
                let success = (try? JITEnableContext.shared.houseArrestDelete(client, path: fullPath)) ?? false
                
                DispatchQueue.main.async {
                    if success {
                        self.loadDirectory()
                    } else {
                        self.errorMessage = error?.localizedDescription ?? "Failed to delete"
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
    
    func renameEntry() {
        guard let entry = selectedRenameEntry, !renameText.isEmpty else { return }
        let oldPath = currentPath + "/" + entry.name
        let newPath = currentPath + "/" + renameText
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let client = self.afcClient else { return }
            
            // Use afc_rename_path (if available) or delete + move
            var error: NSError?
            let result = afc_rename_path(client, oldPath.cString(using: .utf8), newPath.cString(using: .utf8))
            
            DispatchQueue.main.async {
                self.renameText = ""
                self.selectedRenameEntry = nil
                if result == nil {
                    self.loadDirectory()
                } else {
                    self.errorMessage = "Failed to rename: \(String(cString: result!.message))"
                    self.showError = true
                    idevice_error_free(result)
                }
            }
        }
    }
    
    func handleFileImport(_ result: Result<URL, Error>) {
        guard let url = try? result.get() else { return }
        
        // Copy to temp location first (importing sandbox)
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: tempFile)
        try? FileManager.default.copyItem(at: url, to: tempFile)
        
        let devicePath = currentPath + "/" + url.lastPathComponent
        
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            guard let client = self.afcClient else { return }
            let success = (try? JITEnableContext.shared.houseArrestPushFile(
                client,
                fromLocalPath: tempFile.path,
                toDevicePath: devicePath
            )) ?? false
            
            try? FileManager.default.removeItem(at: tempFile)
            
            DispatchQueue.main.async {
                self.isLoading = false
                if success {
                    self.loadDirectory()
                } else {
                    self.errorMessage = error?.localizedDescription ?? "Failed to upload file"
                    self.showError = true
                }
            }
        }
    }
    
    func createFolder() {
        guard !newFolderName.isEmpty else { return }
        let fullPath = currentPath + "/" + newFolderName
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let client = self.afcClient else { return }
            let success = (try? JITEnableContext.shared.houseArrestMakeDirectory(
                client,
                path: fullPath
            )) ?? false
            
            DispatchQueue.main.async {
                self.newFolderName = ""
                if success {
                    self.loadDirectory()
                } else {
                    self.errorMessage = error?.localizedDescription ?? "Failed to create folder"
                    self.showError = true
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    func fileIcon(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "plist": return "doc.plaintext"
        case "json": return "curlybraces"
        case "sqlite", "db", "sqlite3": return "cylinder.fill"
        case "jpg", "jpeg", "png", "gif", "heic", "webp": return "photo"
        case "swift", "m", "h", "c", "cpp", "py", "js", "ts": return "chevron.left.forwardslash.chevron.right"
        case "html", "css": return "chevron.left.forwardslash.chevron.right"
        case "xml": return "doc.text"
        case "log", "txt", "md": return "doc.text"
        case "zip", "ipa", "tar", "gz", "rar", "7z": return "archivebox"
        case "pdf": return "doc.richtext"
        default: return "doc"
        }
    }
    
    func formatSize(_ bytes: UInt64) -> String {
        if bytes == 0 { return "0 B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        let gb = mb / 1024
        return String(format: "%.2f GB", gb)
    }
}
