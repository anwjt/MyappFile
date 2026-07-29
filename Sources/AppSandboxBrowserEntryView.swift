//
//  AppSandboxBrowserEntryView.swift
//  AppFileManager
//
//  Entry view for browsing app sandbox files.
//  Shows a list of installed apps and lets the user select one to browse.
//

import SwiftUI

struct AppSandboxBrowserEntryView: View {
    @State private var apps: [AppInfo] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var selectedCommand: HouseArrestCommand = .vendContainer
    
    struct AppInfo: Identifiable, Hashable {
        let id: String  // bundleId
        let bundleId: String
        let name: String
        let iconData: Data?
        let isSystem: Bool
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
            return lhs.id == rhs.id
        }
    }
    
    var filteredApps: [AppInfo] {
        if searchText.isEmpty {
            return apps
        }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleId.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading app list...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if apps.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "app.badge")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No apps found")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("Make sure LocalDevVPN is running and heartbeat is started.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredApps) { app in
                        NavigationLink {
                            AppSandboxBrowserView(
                                bundleId: app.bundleId,
                                appName: app.name,
                                command: selectedCommand
                            )
                        } label: {
                            HStack(spacing: 12) {
                                if let iconData = app.iconData,
                                   let uiImage = UIImage(data: iconData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                        .cornerRadius(8)
                                } else {
                                    Image(systemName: "app.fill")
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                        .foregroundColor(.blue)
                                        .cornerRadius(8)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .font(.body)
                                        .fontWeight(.medium)
                                    Text(app.bundleId)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("App Sandbox Browser")
            .searchable(text: $searchText, prompt: "Search apps...")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            selectedCommand = .vendContainer
                        } label: {
                            Label("Full Container", systemImage: selectedCommand == .vendContainer ? "checkmark" : "")
                        }
                        
                        Button {
                            selectedCommand = .vendDocuments
                        } label: {
                            Label("Documents Only", systemImage: selectedCommand == .vendDocuments ? "checkmark" : "")
                        }
                        
                        Divider()
                        
                        Button {
                            loadApps()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    if isLoading {
                        ProgressView()
                    }
                }
            }
            .onAppear {
                loadApps()
            }
        }
    }
    
    private func loadApps() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let appsDictAny = (try? JITEnableContext.shared.getAllAppsInfoWithError()) as? [String: Any] ?? [:]

            var results: [AppInfo] = []

            for (bundleId, appInfo) in appsDictAny {
                guard let info = appInfo as? [String: Any] else { continue }

                let name = info["CFBundleDisplayName"] as? String
                        ?? info["CFBundleName"] as? String
                        ?? bundleId
                let isSystem = (info["ApplicationType"] as? String) == "System"

                // Get icon
                let icon = try? JITEnableContext.shared.getAppIcon(withBundleId: bundleId)
                var iconData: Data? = nil
                if let uiImage = icon {
                    iconData = uiImage.pngData()
                }

                results.append(AppInfo(
                    id: bundleId,
                    bundleId: bundleId,
                    name: name,
                    iconData: iconData,
                    isSystem: isSystem
                ))
            }

            // Sort: user apps first, then system apps; within each group sort by name
            results.sort {
                if $0.isSystem != $1.isSystem { return !$0.isSystem }
                return $0.name < $1.name
            }
            
            DispatchQueue.main.async {
                self.apps = results
                self.isLoading = false
            }
        }
    }
}
