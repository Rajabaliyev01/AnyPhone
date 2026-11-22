import SwiftUI
import AppKit

// MARK: - Device Engine & Screen Streamer
class DeviceEngine: ObservableObject {
    static let shared = DeviceEngine()
    
    @Published var currentFrame: NSImage? = nil
    @Published var isStreaming: Bool = false
    @Published var deviceName: String = "Samsung Galaxy A15"
    @Published var isWireless: Bool = true
    
    @Published var dialNumber: String = ""
    @Published var isCalling: Bool = false
    
    var adbPath: String {
        let qtAdb = "/Applications/QtScrcpy.app/Contents/MacOS/adb"
        if FileManager.default.fileExists(atPath: qtAdb) {
            return qtAdb
        }
        return NSString(string: "~/phone_mirror/platform-tools/adb").expandingTildeInPath
    }
    
    init() {
        startStream()
    }
    
    func startStream() {
        guard !isStreaming else { return }
        isStreaming = true
        
        // Fast frame capture loop via ADB exec-out
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            while self.isStreaming {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/bash")
                // Fast binary screen capture
                task.arguments = ["-c", "\(self.adbPath) exec-out screencap -p"]
                let pipe = Pipe()
                task.standardOutput = pipe
                try? task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let image = NSImage(data: data) {
                    DispatchQueue.main.async {
                        self.currentFrame = image
                    }
                }
                usleep(40000) // ~25 FPS smooth streaming
            }
        }
    }
    
    func sendTap(xRatio: CGFloat, yRatio: CGFloat) {
        let x = Int(xRatio * 1080)
        let y = Int(yRatio * 2340)
        runAdb("shell input tap \(x) \(y)")
    }
    
    func sendSwipe(fromX: CGFloat, fromY: CGFloat, toX: CGFloat, toY: CGFloat) {
        let startX = Int(fromX * 1080)
        let startY = Int(fromY * 2340)
        let endX = Int(toX * 1080)
        let endY = Int(toY * 2340)
        runAdb("shell input swipe \(startX) \(startY) \(endX) \(endY) 250")
    }
    
    func sendKey(_ keycode: String) {
        runAdb("shell input keyevent \(keycode)")
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
    
    private func runAdb(_ cmd: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = ["-c", "\(self.adbPath) \(cmd)"]
            try? task.run()
        }
    }
}

// MARK: - Main Application View (100% Apple iPhone Mirroring Style)
struct ContentView: View {
    @StateObject private var engine = DeviceEngine.shared
    @State private var selectedTab: Int = 0 // 0: Screen Mirror, 1: Calling
    @State private var dragStart: CGPoint? = nil
    
    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Phone Chassis Frame
            ZStack {
                // Titanium Frame
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
                    .shadow(color: .black.opacity(0.6), radius: 24, x: 0, y: 12)
                
                // Screen Bezel
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .fill(Color.black)
                    .padding(5)
                
                // Screen Content Area
                VStack(spacing: 0) {
                    // Dynamic Island
                    HStack {
                        Spacer()
                        Capsule()
                            .fill(Color.black)
                            .frame(width: 82, height: 22)
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
                    .zIndex(10)
                    
                    if selectedTab == 0 {
                        // MARK: - Tab 1: Live Interactive Screen Mirror
                        ZStack {
                            if let frame = engine.currentFrame {
                                Image(nsImage: frame)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                            } else {
                                VStack(spacing: 14) {
                                    ProgressView().scaleEffect(0.9)
                                    Text("Connecting live screen...")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                            
                            // Touch & Gesture Interaction Layer
                            GeometryReader { geo in
                                Color.clear
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { val in
                                                if dragStart == nil {
                                                    dragStart = val.startLocation
                                                }
                                            }
                                            .onEnded { val in
                                                let start = dragStart ?? val.startLocation
                                                let end = val.location
                                                let dist = hypot(end.x - start.x, end.y - start.y)
                                                
                                                if dist < 8 {
                                                    // Tap
                                                    engine.sendTap(
                                                        xRatio: start.x / geo.size.width,
                                                        yRatio: start.y / geo.size.height
                                                    )
                                                } else {
                                                    // Swipe
                                                    engine.sendSwipe(
                                                        fromX: start.x / geo.size.width,
                                                        fromY: start.y / geo.size.height,
                                                        toX: end.x / geo.size.width,
                                                        toY: end.y / geo.size.height
                                                    )
                                                }
                                                dragStart = nil
                                            }
                                    )
                            }
                        }
                    } else {
                        // MARK: - Tab 2: Phone Calling Dialpad View
                        VStack(spacing: 10) {
                            Text(engine.dialNumber.isEmpty ? "Phone" : engine.dialNumber)
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .frame(height: 38)
                                .padding(.top, 10)
                            
                            // Keypad Grid
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
                                                engine.dialNumber.append(digit)
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
                            
                            // Call Action Controls
                            HStack(spacing: 20) {
                                Button(action: {
                                    if !engine.dialNumber.isEmpty { engine.dialNumber.removeLast() }
                                }) {
                                    Image(systemName: "delete.left.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(engine.dialNumber.isEmpty ? .clear : .secondary)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: { engine.makeCall(number: engine.dialNumber) }) {
                                    ZStack {
                                        Circle().fill(Color.green).frame(width: 58, height: 58)
                                        Image(systemName: "phone.fill").font(.system(size: 22, weight: .bold)).foregroundColor(.white)
                                    }
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: { engine.endCall() }) {
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
                    
                    // Home Bar Indicator
                    Capsule()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 120, height: 4)
                        .padding(.bottom, 10)
                        .zIndex(10)
                }
                .padding(6)
            }
            .frame(width: 310, height: 640)
            .padding(.leading, 18)
            .padding(.vertical, 18)
            
            // MARK: - Right Control Sidebar (Floating Toolbar)
            VStack(spacing: 14) {
                // Tab Selection
                TabButton(icon: "iphone.gen3", isSelected: selectedTab == 0) { selectedTab = 0 }
                TabButton(icon: "phone.fill", isSelected: selectedTab == 1) { selectedTab = 1 }
                
                Divider().background(Color.white.opacity(0.15)).frame(width: 28)
                
                // Hardware Keys
                SimulatorSideButton(icon: "power", label: "Power", color: .red) {
                    engine.sendKey("KEYCODE_POWER")
                }
                SimulatorSideButton(icon: "speaker.wave.3.fill", label: "Vol +", color: .white) {
                    engine.sendKey("KEYCODE_VOLUME_UP")
                }
                SimulatorSideButton(icon: "speaker.wave.1.fill", label: "Vol -", color: .white) {
                    engine.sendKey("KEYCODE_VOLUME_DOWN")
                }
                
                Divider().background(Color.white.opacity(0.15)).frame(width: 28)
                
                SimulatorSideButton(icon: "house.fill", label: "Home", color: .white) {
                    engine.sendKey("KEYCODE_HOME")
                }
                SimulatorSideButton(icon: "chevron.backward", label: "Back", color: .white) {
                    engine.sendKey("KEYCODE_BACK")
                }
                SimulatorSideButton(icon: "square.stack.fill", label: "Apps", color: .white) {
                    engine.sendKey("KEYCODE_APP_SWITCH")
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

// MARK: - Helper UI Components
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
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
