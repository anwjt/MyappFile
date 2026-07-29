//
//  AppFileManagerApp.swift
//  AppFileManager
//
//  Main entry point. Tab-based UI with:
//  1. Home - Connection status + Device info
//  2. AFC Browse - Browse /var/mobile/Media (standard AFC)
//  3. App Sandbox - Browse app sandbox files via HouseArrest
//  4. Settings - About, credits, info
//

import SwiftUI

@main
struct AppFileManagerApp: App {
    @StateObject private var viewModel = AppFileManagerViewModel()
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(viewModel)
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @EnvironmentObject var viewModel: AppFileManagerViewModel
    
    var body: some View {
        TabView {
            NavigationStack {
                ConnectionView()
            }
            .tabItem {
                Label("Home", systemImage: "link")
            }
            
            NavigationStack {
                AFCBrowseView()
            }
            .tabItem {
                Label("AFC", systemImage: "folder.fill")
            }
            
            NavigationStack {
                AppSandboxBrowserEntryView()
            }
            .tabItem {
                Label("App Sandbox", systemImage: "app.badge")
            }
            
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}

// MARK: - Connection View

struct ConnectionView: View {
    @EnvironmentObject var viewModel: AppFileManagerViewModel
    
    var body: some View {
        Form {
            Section("Connection Status") {
                HStack {
                    Image(systemName: viewModel.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(viewModel.isConnected ? .green : .red)
                        .font(.title2)
                    VStack(alignment: .leading) {
                        Text(viewModel.isConnected ? "Connected" : "Disconnected")
                            .font(.headline)
                        Text(viewModel.connectionStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            Section("How to Connect") {
                Text("1. Install and open **LocalDevVPN** from the App Store")
                Text("2. Turn on Wi-Fi (or Airplane Mode)")
                Text("3. In LocalDevVPN, tap **Start** to activate the VPN tunnel")
                Text("4. Come back to this app")
                Text("5. Tap **Start Heartbeat** to connect to your device")
            }
            
            Section("Device Info") {
                if let info = viewModel.deviceInfo {
                    LabeledContent("UDID", value: info.udid)
                    LabeledContent("iOS Version", value: info.iosVersion)
                    LabeledContent("Device Name", value: info.deviceName)
                } else {
                    Text("Not connected yet")
                        .foregroundColor(.secondary)
                }
            }
            
            Section {
                Button(action: { viewModel.startHeartbeat() }) {
                    Label("Start Heartbeat", systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(viewModel.isConnected)
                
                if viewModel.isConnected {
                    Button(action: { viewModel.stopHeartbeat() }) {
                        Label("Stop Heartbeat", systemImage: "stop.circle")
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Home")
        .onAppear {
            viewModel.checkConnection()
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    var body: some View {
        Form {
            Section("About") {
                LabeledContent("App", value: "App File Manager")
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Based on", value: "SparseBox idevice library")
            }
            
            Section("Credits") {
                Link(destination: URL(string: "https://github.com/khanhduytran0/SparseBox")!) {
                    Label("SparseBox by khanhduytran0", systemImage: "link")
                }
                Link(destination: URL(string: "https://github.com/jkcoxson/minimuxer")!) {
                    Label("minimuxer by jkcoxson", systemImage: "link")
                }
                Link(destination: URL(string: "https://github.com/seomin0610/LocalDevVPN")!) {
                    Label("LocalDevVPN by seomin0610", systemImage: "link")
                }
                Link(destination: URL(string: "https://github.com/libimobiledevice")!) {
                    Label("libimobiledevice", systemImage: "link")
                }
            }
            
            Section("Note") {
                Text("This app accesses app sandbox files through the HouseArrest protocol, the same protocol used by 3uTools and iMazing on computers. All operations happen directly on your device without needing a computer.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}

// MARK: - View Model

class AppFileManagerViewModel: ObservableObject {
    @Published var isConnected = false
    @Published var connectionStatus = "Not started. Start heartbeat to connect."
    @Published var deviceInfo: DeviceInfo?
    
    struct DeviceInfo {
        let udid: String
        let iosVersion: String
        let deviceName: String
    }
    
    func checkConnection() {
        DispatchQueue.global(qos: .userInitiated).async {
            let hasProvider = JITEnableContext.shared.getTcpProviderHandle() != nil
            DispatchQueue.main.async {
                self.isConnected = hasProvider
                if hasProvider {
                    self.connectionStatus = "LocalDevVPN tunnel active"
                    self.loadDeviceInfo()
                } else {
                    self.connectionStatus = "LocalDevVPN not detected. Please start LocalDevVPN first."
                }
            }
        }
    }
    
    func startHeartbeat() {
        connectionStatus = "Starting heartbeat..."
        DispatchQueue.global(qos: .userInitiated).async {
            let success = JITEnableContext.shared.startHeartbeat(nil)

            DispatchQueue.main.async {
                if success {
                    self.isConnected = true
                    self.connectionStatus = "Connected! Heartbeat active."
                    self.loadDeviceInfo()
                } else {
                    self.isConnected = false
                    self.connectionStatus = "Failed to start heartbeat"
                }
            }
        }
    }
    
    func stopHeartbeat() {
        // Free provider to stop heartbeat
        if let provider = JITEnableContext.shared.getTcpProviderHandle() {
            idevice_provider_free(provider)
        }
        isConnected = false
        connectionStatus = "Heartbeat stopped."
    }
    
    func loadDeviceInfo() {
        DispatchQueue.global(qos: .userInitiated).async {
            // Use ideviceInfoInit to get lockdown client, then parse XML for device info
            let lockdownClient = JITEnableContext.shared.ideviceInfoInit(nil)

            if let lockdownClient = lockdownClient {
                // Get all values as XML plist
                let xmlPtr = JITEnableContext.shared.ideviceInfoGetXMLWithLockdownClient(lockdownClient, error: nil)

                if let xml = xmlPtr {
                    let xmlString = String(cString: xml)
                    free(xml)

                    // Parse XML to extract device info
                    self.parseDeviceInfo(from: xmlString)
                }

                lockdownd_client_free(lockdownClient)
            } else {
                DispatchQueue.main.async {
                    self.connectionStatus = "Failed to get device info"
                }
            }
        }
    }
    
    private func parseDeviceInfo(from xmlString: String) {
        // Parse the lockdownd XML plist to extract device info
        let info = NSMutableDictionary()
        
        // Simple XML parsing for lockdownd plist
        let keys = xmlString.components(separatedBy: "<key>")
        for i in 0..<keys.count - 1 {
            let keySection = keys[i + 1]
            guard let keyEnd = keySection.range(of: "</key>") else { continue }
            let key = String(keySection[keySection.startIndex..<keyEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Get the next value after this key
            let remaining = keys[i + 1]
            let valueSection = String(remaining[keyEnd.upperBound...])
            
            // Check for <string> value
            if let stringStart = valueSection.range(of: "<string>"),
               let stringEnd = valueSection.range(of: "</string>") {
                let value = String(valueSection[stringStart.upperBound..<stringEnd.lowerBound])
                info[key] = value
            }
        }
        
        let udid = info["UniqueDeviceID"] as? String ?? "Unknown"
        let deviceName = info["DeviceName"] as? String ?? "Unknown"
        let productVersion = info["ProductVersion"] as? String ?? "Unknown"
        
        DispatchQueue.main.async {
            self.deviceInfo = DeviceInfo(
                udid: udid,
                iosVersion: productVersion,
                deviceName: deviceName
            )
        }
    }
}
