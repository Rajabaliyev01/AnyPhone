import SwiftUI
import AppKit

// MARK: - AnyPhone Device Manager
class AnyPhoneManager: ObservableObject {
    static let shared = AnyPhoneManager()
    
    @Published var isConnected: Bool = false
    @Published var deviceName: String = "Samsung Galaxy A15"
    @Published var connectionMode: String = "Wi-Fi (Wireless)"
    
    @Published var isCalling: Bool = false
    @Published var callDuration: String = "00:00"
    @Published var isMuted: Bool = false
    @Published var isSpeakerOn: Bool = true
    
    var adbPath: String {
        let qtAdb = "/Applications/QtScrcpy.app/Contents/MacOS/adb"
        if FileManager.default.fileExists(atPath: qtAdb) {
            return qtAdb
        }
        return NSString(string: "~/phone_mirror/platform-tools/adb").expandingTildeInPath
    }
    
    func startMirroring() {
        // Connect to AnyPhone server and open stream
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = ["-c", "\(self.adbPath) shell am start -a android.intent.action.MAIN -c android.intent.category.HOME"]
            try? task.run()
        }
    }
    
    func makeCall(number: String) {
        guard !number.isEmpty else { return }
        let clean = number.replacingOccurrences(of: "#", with: "%23").replacingOccurrences(of: "+", with: "%2B")
        runAdb("shell am start -a android.intent.action.CALL -d tel:\(clean)")
        self.isCalling = true
    }
    
    func endCall() {
        runAdb("shell input keyevent KEYCODE_ENDCALL")
        self.isCalling = false
    }
    
    func pressKey(_ keycode: String) {
        runAdb("shell input keyevent \(keycode)")
    }
    
    private func runAdb(_ cmd: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = ["-c", "\(self.adbPath) \(cmd)"]
            try? task.run()
        }
    }
}

// MARK: - Main Native AnyPhone Window (iPhone Mirroring Aesthetic)
struct AnyPhoneAppView: View {
    @StateObject private var manager = AnyPhoneManager.shared
    @State private var selectedTab: Int = 0 // 0: Screen Mirror, 1: Phone Calls, 2: Settings
    @State private var dialNumber: String = ""
    
    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Left Phone Viewport (Apple Simulator Frame)
            ZStack {
                // Titanium chassis frame
                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .fill(Color(white: 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 44, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.3), Color.white.opacity(0.08)],
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
                
                // Display Content
                VStack(spacing: 0) {
                    // Top Notch / Speaker
                    HStack {
                        Spacer()
                        Capsule()
                            .fill(Color.black)
                            .frame(width: 76, height: 20)
                            .overlay(
                                Circle()
                                    .fill(Color(white: 0.2))
                                    .frame(width: 8, height: 8)
                                    .padding(.trailing, 22),
                                alignment: .trailing
                            )
                        Spacer()
                    }
                    .padding(.top, 12)
                    
                    if selectedTab == 0 {
                        // Screen Mirror View
                        VStack(spacing: 16) {
                            Spacer()
                            Image(systemName: "iphone.gen3")
                                .font(.system(size: 54, weight: .light))
                                .foregroundColor(.white.opacity(0.35))
                            
                            Text(manager.deviceName)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Text(manager.connectionMode)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.green)
                            
                            Button(action: {
                                manager.startMirroring()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 11))
                                    Text("Open Live Display")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.blue))
                            }
                            .buttonStyle(.plain)
                            
                            Spacer()
                        }
                    } else if selectedTab == 1 {
                        // Calling Dialpad View
                        VStack(spacing: 12) {
                            Text(dialNumber.isEmpty ? "Phone" : dialNumber)
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(height: 36)
                                .padding(.top, 10)
                            
                            // Keypad
                            VStack(spacing: 8) {
                                ForEach([
                                    ["1", "2", "3"],
                                    ["4", "5", "6"],
                                    ["7", "8", "9"],
                                    ["*", "0", "#"]
                                ], id: \.self) { row in
                                    HStack(spacing: 14) {
                                        ForEach(row, id: \.self) { digit in
                                            Button(action: { dialNumber.append(digit) }) {
                                                Text(digit)
                                                    .font(.system(size: 22, weight: .medium, design: .rounded))
                                                    .foregroundColor(.white)
                                                    .frame(width: 54, height: 54)
                                                    .background(Circle().fill(Color(white: 0.18)))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            
                            HStack(spacing: 20) {
                                Button(action: { if !dialNumber.isEmpty { dialNumber.removeLast() } }) {
                                    Image(systemName: "delete.left.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(dialNumber.isEmpty ? .clear : .secondary)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: { manager.makeCall(number: dialNumber) }) {
                                    ZStack {
                                        Circle().fill(Color.green).frame(width: 58, height: 58)
                                        Image(systemName: "phone.fill").font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                                    }
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: { manager.endCall() }) {
                                    ZStack {
                                        Circle().fill(Color.red).frame(width: 48, height: 48)
                                        Image(systemName: "phone.down.fill").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.top, 4)
                        }
                    }
                    
                    Spacer()
                    
                    // Home Bar
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
                // Tab Selectors
                Group {
                    TabButton(icon: "iphone.gen3", isSelected: selectedTab == 0) { selectedTab = 0 }
                    TabButton(icon: "phone.fill", isSelected: selectedTab == 1) { selectedTab = 1 }
                }
                
                Divider().background(Color.white.opacity(0.15)).frame(width: 28)
                
                // Hardware Keys
                SimulatorSideButton(icon: "power", label: "Power", color: .red) {
                    manager.pressKey("KEYCODE_POWER")
                }
                SimulatorSideButton(icon: "speaker.wave.3.fill", label: "Vol +", color: .white) {
                    manager.pressKey("KEYCODE_VOLUME_UP")
                }
                SimulatorSideButton(icon: "speaker.wave.1.fill", label: "Vol -", color: .white) {
                    manager.pressKey("KEYCODE_VOLUME_DOWN")
                }
                
                Divider().background(Color.white.opacity(0.15)).frame(width: 28)
                
                SimulatorSideButton(icon: "house.fill", label: "Home", color: .white) {
                    manager.pressKey("KEYCODE_HOME")
                }
                SimulatorSideButton(icon: "chevron.backward", label: "Back", color: .white) {
                    manager.pressKey("KEYCODE_BACK")
                }
                SimulatorSideButton(icon: "square.stack.fill", label: "Apps", color: .white) {
                    manager.pressKey("KEYCODE_APP_SWITCH")
                }
                
                Spacer()
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 10)
            .frame(width: 66)
        }
        .background(VisualEffectView().ignoresSafeArea())
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
