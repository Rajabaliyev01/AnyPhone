import SwiftUI
import AppKit

// MARK: - Main Application View
struct AnyPhoneAppView: View {
    @StateObject private var detector = DeviceDetector.shared
    @State private var selectedTab: Int = 0 // 0: Screen Mirror, 1: Calling, 2: Devices
    @State private var dialNumber: String = ""
    @State private var isConnectingWifi: Bool = false
    
    var currentDevice: DiscoveredDevice? {
        detector.selectedDevice
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Phone Chassis Frame
            ZStack {
                // Titanium Outer Chassis
                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .fill(Color(white: 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 44, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: .black.opacity(0.55), radius: 24, x: 0, y: 12)
                
                // Screen Bezel
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .fill(Color(white: 0.05))
                    .padding(6)
                
                // Screen Content Area
                VStack(spacing: 0) {
                    // Dynamic Island
                    HStack {
                        Spacer()
                        Capsule()
                            .fill(Color.black)
                            .frame(width: 80, height: 22)
                            .overlay(
                                Circle()
                                    .fill(Color(white: 0.2))
                                    .frame(width: 8, height: 8)
                                    .padding(.trailing, 24),
                                alignment: .trailing
                            )
                        Spacer()
                    }
                    .padding(.top, 10)
                    
                    if selectedTab == 0 {
                        // MARK: - Mirroring View
                        VStack(spacing: 16) {
                            Spacer()
                            
                            Image(systemName: currentDevice?.isWireless == true ? "wifi" : "cable.connector")
                                .font(.system(size: 44, weight: .light))
                                .foregroundColor(.white.opacity(0.5))
                            
                            Text(currentDevice?.model ?? "No Device Connected")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            
                            if let dev = currentDevice {
                                HStack(spacing: 6) {
                                    Circle().fill(dev.status == "device" ? Color.green : Color.orange).frame(width: 7, height: 7)
                                    Text(dev.isWireless ? "Connected via Wi-Fi" : "Connected via USB")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(dev.status == "device" ? .green : .orange)
                                }
                                
                                if !dev.isWireless {
                                    Button(action: {
                                        isConnectingWifi = true
                                        detector.enableWirelessMode(for: dev) { _ in
                                            isConnectingWifi = false
                                        }
                                    }) {
                                        HStack(spacing: 6) {
                                            if isConnectingWifi {
                                                ProgressView().scaleEffect(0.6)
                                            } else {
                                                Image(systemName: "wifi")
                                            }
                                            Text("Switch to Wireless (Wi-Fi)")
                                                .font(.system(size: 11, weight: .semibold))
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 7)
                                        .background(Capsule().fill(Color.purple.opacity(0.8)))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 4)
                                }
                            }
                            
                            Spacer()
                        }
                    } else if selectedTab == 1 {
                        // MARK: - Phone Calling View
                        VStack(spacing: 10) {
                            Text(dialNumber.isEmpty ? "Phone" : dialNumber)
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(height: 38)
                                .padding(.top, 10)
                            
                            VStack(spacing: 8) {
                                ForEach([
                                    ["1", "2", "3"],
                                    ["4", "5", "6"],
                                    ["7", "8", "9"],
                                    ["*", "0", "#"]
                                ], id: \.self) { row in
                                    HStack(spacing: 14) {
                                        ForEach(row, id: \.self) { digit in
                                            Button(action: {
                                                dialNumber.append(digit)
                                                NSSound.beep()
                                            }) {
                                                Text(digit)
                                                    .font(.system(size: 22, weight: .medium, design: .rounded))
                                                    .foregroundColor(.white)
                                                    .frame(width: 52, height: 52)
                                                    .background(Circle().fill(Color(white: 0.18)))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            
                            HStack(spacing: 20) {
                                Button(action: {
                                    if !dialNumber.isEmpty { dialNumber.removeLast() }
                                }) {
                                    Image(systemName: "delete.left.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(dialNumber.isEmpty ? .clear : .secondary)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: { makeCall(number: dialNumber) }) {
                                    ZStack {
                                        Circle().fill(Color.green).frame(width: 58, height: 58)
                                        Image(systemName: "phone.fill").font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                                    }
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: { endCall() }) {
                                    ZStack {
                                        Circle().fill(Color.red).frame(width: 48, height: 48)
                                        Image(systemName: "phone.down.fill").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.top, 4)
                        }
                    } else {
                        // MARK: - Devices Manager View
                        VStack(spacing: 14) {
                            Text("Available Devices")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.top, 14)
                            
                            ScrollView {
                                VStack(spacing: 8) {
                                    ForEach(detector.devices) { dev in
                                        Button(action: { detector.selectedDevice = dev }) {
                                            HStack {
                                                Image(systemName: dev.isWireless ? "wifi" : "cable.connector")
                                                    .foregroundColor(dev.id == currentDevice?.id ? .blue : .secondary)
                                                
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(dev.model)
                                                        .font(.system(size: 13, weight: .medium))
                                                        .foregroundColor(.white)
                                                    Text(dev.id)
                                                        .font(.system(size: 10))
                                                        .foregroundColor(.secondary)
                                                }
                                                Spacer()
                                                if dev.id == currentDevice?.id {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(.blue)
                                                }
                                            }
                                            .padding(10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(dev.id == currentDevice?.id ? Color.blue.opacity(0.2) : Color(white: 0.12))
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 10)
                            }
                            
                            Button(action: { detector.refreshDevices() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Scan for Devices")
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 14)
                        }
                    }
                    
                    Spacer()
                    
                    // Home Indicator
                    Capsule()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 120, height: 4)
                        .padding(.bottom, 12)
                }
                .padding(8)
            }
            .frame(width: 310, height: 640)
            .padding(.leading, 18)
            .padding(.vertical, 18)
            
            // MARK: - Right Control Sidebar
            VStack(spacing: 14) {
                TabButton(icon: "iphone.gen3", isSelected: selectedTab == 0) { selectedTab = 0 }
                TabButton(icon: "phone.fill", isSelected: selectedTab == 1) { selectedTab = 1 }
                TabButton(icon: "antenna.radiowaves.left.and.right", isSelected: selectedTab == 2) { selectedTab = 2 }
                
                Divider().background(Color.white.opacity(0.15)).frame(width: 28)
                
                SimulatorSideButton(icon: "power", label: "Power", color: .red) {
                    sendKey("KEYCODE_POWER")
                }
                SimulatorSideButton(icon: "speaker.wave.3.fill", label: "Vol +", color: .white) {
                    sendKey("KEYCODE_VOLUME_UP")
                }
                SimulatorSideButton(icon: "speaker.wave.1.fill", label: "Vol -", color: .white) {
                    sendKey("KEYCODE_VOLUME_DOWN")
                }
                
                Divider().background(Color.white.opacity(0.15)).frame(width: 28)
                
                SimulatorSideButton(icon: "house.fill", label: "Home", color: .white) {
                    sendKey("KEYCODE_HOME")
                }
                SimulatorSideButton(icon: "chevron.backward", label: "Back", color: .white) {
                    sendKey("KEYCODE_BACK")
                }
                SimulatorSideButton(icon: "square.stack.fill", label: "Apps", color: .white) {
                    sendKey("KEYCODE_APP_SWITCH")
                }
                
                Spacer()
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 10)
            .frame(width: 66)
        }
        .background(VisualEffectView().ignoresSafeArea())
    }
    
    func makeCall(number: String) {
        guard !number.isEmpty, let dev = currentDevice else { return }
        let clean = number.replacingOccurrences(of: "#", with: "%23").replacingOccurrences(of: "+", with: "%2B")
        runAdb("-s \(dev.id) shell am start -a android.intent.action.CALL -d tel:\(clean)")
    }
    
    func endCall() {
        guard let dev = currentDevice else { return }
        runAdb("-s \(dev.id) shell input keyevent KEYCODE_ENDCALL")
    }
    
    func sendKey(_ keycode: String) {
        guard let dev = currentDevice else { return }
        runAdb("-s \(dev.id) shell input keyevent \(keycode)")
    }
    
    func runAdb(_ cmd: String) {
        let path = detector.adbPath
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = ["-c", "\(path) \(cmd)"]
            try? task.run()
        }
    }
}

struct TabButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isSelected ? .white : .secondary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(isSelected ? Color.blue : Color(white: 0.18)))
        }
        .buttonStyle(.plain)
    }
}

struct SimulatorSideButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color(white: 0.18)))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }
}

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .hudWindow
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

@main
struct AnyPhoneApp: App {
    var body: some Scene {
        WindowGroup {
            AnyPhoneAppView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
