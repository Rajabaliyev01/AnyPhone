import Foundation
import Combine

struct DiscoveredDevice: Identifiable, Hashable {
    let id: String         // Serial or IP:Port
    let model: String      // E.g. Galaxy A15, Pixel 7
    let isWireless: Bool   // USB vs Wi-Fi
    let status: String     // device, unauthorized, offline
}

class DeviceDetector: ObservableObject {
    static let shared = DeviceDetector()
    
    @Published var devices: [DiscoveredDevice] = []
    @Published var selectedDevice: DiscoveredDevice? = nil
    
    var adbPath: String {
        let qtAdb = "/Applications/QtScrcpy.app/Contents/MacOS/adb"
        if FileManager.default.fileExists(atPath: qtAdb) {
            return qtAdb
        }
        return NSString(string: "~/phone_mirror/platform-tools/adb").expandingTildeInPath
    }
    
    private var timer: Timer?
    
    init() {
        refreshDevices()
        // Poll every 3 seconds for plug/unplug of USB or Wi-Fi
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshDevices()
        }
    }
    
    func refreshDevices() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let output = self.runAdbCommand("devices -l")
            var detected: [DiscoveredDevice] = []
            
            let lines = output.components(separatedBy: "\n")
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || trimmed.starts(with: "List of devices") || trimmed.starts(with: "*") {
                    continue
                }
                
                let parts = trimmed.split(separator: " ").map(String.init)
                guard parts.count >= 2 else { continue }
                
                let deviceId = parts[0]
                let status = parts[1]
                let isWireless = deviceId.contains(":")
                
                // Extract model name if available
                var modelName = isWireless ? "Wireless Device" : "Android Device"
                for part in parts {
                    if part.starts(with: "model:") {
                        modelName = part.replacingOccurrences(of: "model:", with: "").replacingOccurrences(of: "_", with: " ")
                    }
                }
                
                let dev = DiscoveredDevice(
                    id: deviceId,
                    model: modelName,
                    isWireless: isWireless,
                    status: status
                )
                detected.append(dev)
            }
            
            DispatchQueue.main.async {
                self.devices = detected
                if self.selectedDevice == nil || !detected.contains(where: { $0.id == self.selectedDevice?.id }) {
                    self.selectedDevice = detected.first
                }
            }
        }
    }
    
    // Switch a USB device to Wireless (Wi-Fi) mode
    func enableWirelessMode(for device: DiscoveredDevice, completion: @escaping (String?) -> Void) {
        guard !device.isWireless else {
            completion(device.id)
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            // 1. Get device IP address
            let ipOutput = self.runAdbCommand("-s \(device.id) shell ip -f inet addr show wlan0")
            var ip: String? = nil
            for line in ipOutput.components(separatedBy: "\n") {
                if line.contains("inet ") {
                    let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
                    if parts.count >= 2 {
                        ip = parts[1].components(separatedBy: "/").first
                        break
                    }
                }
            }
            
            // 2. Enable TCP/IP on port 5555
            _ = self.runAdbCommand("-s \(device.id) tcpip 5555")
            Thread.sleep(forTimeInterval: 1.0)
            
            // 3. Connect to IP
            if let ip = ip {
                _ = self.runAdbCommand("connect \(ip):5555")
                DispatchQueue.main.async {
                    self.refreshDevices()
                    completion("\(ip):5555")
                }
            } else {
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }
    
    private func runAdbCommand(_ cmd: String) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "\(self.adbPath) \(cmd)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try? task.run()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
