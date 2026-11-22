import SwiftUI
import AppKit
import AVFoundation

// MARK: - Native Metal / VideoToolbox Stream View with Real-time Touch & Hold
struct HardwareVideoView: NSViewRepresentable {
    @ObservedObject var controller = EngineController.shared
    
    func makeNSView(context: Context) -> InteractiveScreenView {
        let view = InteractiveScreenView()
        view.controller = controller
        
        let player = H264StreamPlayer.shared
        player.sampleBufferLayer.frame = view.bounds
        player.sampleBufferLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        player.sampleBufferLayer.cornerRadius = 34
        player.sampleBufferLayer.masksToBounds = true
        
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.layer?.addSublayer(player.sampleBufferLayer)
        
        player.startStream(serial: controller.activeSerial)
        return view
    }
    
    func updateNSView(_ nsView: InteractiveScreenView, context: Context) {
        nsView.controller = controller
        if let layer = nsView.layer?.sublayers?.first as? AVSampleBufferDisplayLayer {
            layer.frame = nsView.bounds
        }
    }
}

// MARK: - Interactive Screen View for Real-time Mouse Down / Hold / Drag / Up
class InteractiveScreenView: NSView {
    weak var controller: EngineController?
    private var isPressing = false
    private var pressStartTime: Date?
    private var startPoint: CGPoint = .zero
    private var lastPoint: CGPoint = .zero
    private var hasMoved = false
    
    override var acceptsFirstResponder: Bool { true }
    
    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        // Flip Y for macOS coordinate system (macOS is bottom-left, Android is top-left)
        let normalizedY = bounds.height - loc.y
        let rx = max(0, min(1, loc.x / bounds.width))
        let ry = max(0, min(1, normalizedY / bounds.height))
        
        isPressing = true
        pressStartTime = Date()
        startPoint = CGPoint(x: rx, y: ry)
        lastPoint = startPoint
        hasMoved = false
        
        // Immediately send DOWN event to Android
        controller?.sendTouchEvent(action: "DOWN", xRatio: rx, yRatio: ry)
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isPressing else { return }
        let loc = convert(event.locationInWindow, from: nil)
        let normalizedY = bounds.height - loc.y
        let rx = max(0, min(1, loc.x / bounds.width))
        let ry = max(0, min(1, normalizedY / bounds.height))
        
        let dist = hypot(rx - lastPoint.x, ry - lastPoint.y)
        if dist > 0.008 { // Throttle slightly to ensure smooth 60fps tracking
            hasMoved = true
            lastPoint = CGPoint(x: rx, y: ry)
            controller?.sendTouchEvent(action: "MOVE", xRatio: rx, yRatio: ry)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        guard isPressing else { return }
        let loc = convert(event.locationInWindow, from: nil)
        let normalizedY = bounds.height - loc.y
        let rx = max(0, min(1, loc.x / bounds.width))
        let ry = max(0, min(1, normalizedY / bounds.height))
        
        // Send UP event to conclude tap, long-press, or drag
        controller?.sendTouchEvent(action: "UP", xRatio: rx, yRatio: ry)
        
        isPressing = false
        pressStartTime = nil
    }
}

// MARK: - Controller (Touch & Phone Actions & Multi-connection USB/Wi-Fi)
class EngineController: ObservableObject {
    static let shared = EngineController()
    
    @Published var isPhysicalScreenOff: Bool = false
    @Published var connectionMode: String = "Wi-Fi" // "USB" or "Wi-Fi"
    @Published var activeSerial: String = "192.168.100.162:5555"
    @Published var isConnected: Bool = true
    
    var adbPath: String {
        let qtAdb = "/Applications/QtScrcpy.app/Contents/MacOS/adb"
        if FileManager.default.fileExists(atPath: qtAdb) {
            return qtAdb
        }
        return NSString(string: "~/phone_mirror/platform-tools/adb").expandingTildeInPath
    }
    
    init() {
        refreshDevices()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            ScrcpyControlManager.shared.ensureControlService(adbPath: self.adbPath, serial: self.activeSerial)
        }
    }
    
    func refreshDevices() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let out = self.runAdbSync("devices")
            let lines = out.components(separatedBy: .newlines)
            var wifiDevice: String? = nil
            var usbDevice: String? = nil
            
            for line in lines where line.contains("\tdevice") {
                let parts = line.components(separatedBy: "\t")
                if let dev = parts.first?.trimmingCharacters(in: .whitespaces) {
                    if dev.contains(":") {
                        wifiDevice = dev
                    } else {
                        usbDevice = dev
                    }
                }
            }
            
            DispatchQueue.main.async {
                if self.connectionMode == "Wi-Fi" && wifiDevice != nil {
                    self.activeSerial = wifiDevice!
                    self.isConnected = true
                } else if let usb = usbDevice {
                    self.activeSerial = usb
                    self.connectionMode = "USB"
                    self.isConnected = true
                } else if let wifi = wifiDevice {
                    self.activeSerial = wifi
                    self.connectionMode = "Wi-Fi"
                    self.isConnected = true
                } else {
                    self.isConnected = false
                }
            }
        }
    }
    
    func switchToWiFi() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            _ = self.runAdbSync("tcpip 5555")
            let ipRoute = self.runAdbSync("shell ip route")
            var ip = "192.168.100.162"
            if let range = ipRoute.range(of: "src ") {
                let sub = ipRoute[range.upperBound...]
                let foundIp = sub.components(separatedBy: .whitespaces).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if foundIp.contains(".") {
                    ip = foundIp
                }
            }
            _ = self.runAdbSync("connect \(ip):5555")
            
            DispatchQueue.main.async {
                self.activeSerial = "\(ip):5555"
                self.connectionMode = "Wi-Fi"
                H264StreamPlayer.shared.restartStream(serial: self.activeSerial)
            }
        }
    }
    
    func switchToUSB() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let out = self.runAdbSync("devices")
            let lines = out.components(separatedBy: .newlines)
            var usb: String? = nil
            for line in lines where line.contains("\tdevice") {
                let d = line.components(separatedBy: "\t").first?.trimmingCharacters(in: .whitespaces) ?? ""
                if !d.contains(":") && !d.isEmpty {
                    usb = d
                    break
                }
            }
            
            DispatchQueue.main.async {
                if let usb = usb {
                    self.activeSerial = usb
                    self.connectionMode = "USB"
                    H264StreamPlayer.shared.restartStream(serial: self.activeSerial)
                }
            }
        }
    }
    
    func toggleConnectionMode() {
        if connectionMode == "Wi-Fi" {
            switchToUSB()
        } else {
            switchToWiFi()
        }
    }
    
    // MARK: - Real-time Touch Events (DOWN, MOVE, UP, HOLD)
    func sendTouchEvent(action: String, xRatio: CGFloat, yRatio: CGFloat) {
        let x = Int(xRatio * 1080)
        let y = Int(yRatio * 2340)
        runAdb("shell input motionevent \(action) \(x) \(y)")
    }
    
    func takeScreenshot() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dest = NSString(string: "~/Downloads/AnyPhone_\(formatter.string(from: Date())).png").expandingTildeInPath
        runAdb("exec-out screencap -p > \"\(dest)\"")
    }
    
    func togglePhysicalScreen() {
        isPhysicalScreenOff.toggle()
        ScrcpyControlManager.shared.setScreenPowerMode(off: isPhysicalScreenOff)
    }
    
    func sendKey(_ key: String) {
        runAdb("shell input keyevent \(key)")
    }
    
    @Published var isSpeakerOn: Bool = false
    
    func toggleHandsfreeSpeaker() {
        isSpeakerOn.toggle()
        if isSpeakerOn {
            // Android apparatli spikerfonni ochish va ovozni maksimal chiqarish
            runAdb("shell cmd audio set-preferred-output-device BUILTIN_SPEAKER")
            runAdb("shell cmd audio set-volume 0 5")
            runAdb("shell input keyevent KEYCODE_SPEAKERPHONE")
        } else {
            // Standart quloq rejimiga qaytarish
            runAdb("shell cmd audio set-preferred-output-device AUTO")
            runAdb("shell input keyevent KEYCODE_SPEAKERPHONE")
        }
    }
    
    func syncClipboardToPhone() {
        if let str = NSPasteboard.general.string(forType: .string) {
            let encoded = str.replacingOccurrences(of: " ", with: "%s")
            runAdb("shell input text \"\(encoded)\"")
        }
    }
    
    private func runAdb(_ cmd: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            let target = self.activeSerial.isEmpty ? "" : "-s \(self.activeSerial)"
            task.arguments = ["-c", "\(self.adbPath) \(target) \(cmd)"]
            try? task.run()
        }
    }
    
    private func runAdbSync(_ cmd: String) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "\(self.adbPath) \(cmd)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Main Phone Chassis View
struct PhoneChassisView: View {
    @StateObject private var controller = EngineController.shared
    
    var body: some View {
        ZStack {
            // Premium macOS Frosted Glass Background
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            HStack(spacing: 24) {
                // MARK: - Apple Titanium Phone Chassis
                ZStack {
                    // Outer Titanium Bezel
                    RoundedRectangle(cornerRadius: 50, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(white: 0.28), Color(white: 0.14), Color(white: 0.22)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 376, height: 792)
                        .shadow(color: .black.opacity(0.65), radius: 35, x: 0, y: 18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 50, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.35), Color.clear, Color.black.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2.5
                                )
                        )
                    
                    // Inner Screen Border
                    RoundedRectangle(cornerRadius: 42, style: .continuous)
                        .fill(Color.black)
                        .frame(width: 362, height: 778)
                    
                    // Display Area (Interactive Screen with Real-Time Hold, Tap, Drag)
                    ZStack {
                        HardwareVideoView(controller: controller)
                            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                            .frame(width: 352, height: 768)
                        
                        // Dynamic Island (Apple iPhone style)
                        VStack {
                            HStack {
                                Spacer()
                                Capsule()
                                    .fill(Color.black)
                                    .frame(width: 105, height: 26)
                                    .overlay(
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(Color.black)
                                                .frame(width: 11, height: 11)
                                                .overlay(
                                                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 1)
                                                )
                                            Spacer()
                                            Circle()
                                                .fill(Color(white: 0.15))
                                                .frame(width: 9, height: 9)
                                        }
                                        .padding(.horizontal, 10)
                                    )
                                    .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
                                Spacer()
                            }
                            .padding(.top, 11)
                            
                            Spacer()
                            
                            // Home Indicator Bar
                            Capsule()
                                .fill(Color.white.opacity(0.75))
                                .frame(width: 125, height: 4.5)
                                .padding(.bottom, 8)
                                .onTapGesture {
                                    controller.sendKey("KEYCODE_HOME")
                                }
                        }
                        .allowsHitTesting(false) // Allows touches to reach screen view underneath
                    }
                    .frame(width: 352, height: 768)
                }
                
                // MARK: - Quick Action HUD Sidebar
                VStack(spacing: 12) {
                    Group {
                        // Wi-Fi / USB Connection Status Pill Button
                        Button(action: {
                            controller.toggleConnectionMode()
                        }) {
                            VStack(spacing: 3) {
                                Image(systemName: controller.connectionMode == "Wi-Fi" ? "wifi" : "cable.connector")
                                    .font(.system(size: 14, weight: .bold))
                                Text(controller.connectionMode)
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(controller.connectionMode == "Wi-Fi" ? Color.cyan.opacity(0.4) : Color.green.opacity(0.4))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(controller.connectionMode == "Wi-Fi" ? Color.cyan : Color.green, lineWidth: 1.5)
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Wi-Fi va USB o'rtasida almashtirish")
                        
                        // Handsfree Speakerphone Toggle
                        SidebarIconButton(
                            icon: controller.isSpeakerOn ? "speaker.wave.3.bubble.fill" : "speaker.wave.2.fill",
                            color: controller.isSpeakerOn ? .green : .indigo
                        ) {
                            controller.toggleHandsfreeSpeaker()
                        }
                        .help("Handsfree Spikerfon (stol ustidan erkin gaplashish)")
                        
                        Divider().background(Color.white.opacity(0.2))
                        
                        SidebarIconButton(icon: "power", color: .red) {
                            controller.sendKey("KEYCODE_POWER")
                        }
                        SidebarIconButton(icon: "speaker.wave.3.fill", color: .blue) {
                            controller.sendKey("KEYCODE_VOLUME_UP")
                        }
                        SidebarIconButton(icon: "speaker.wave.1.fill", color: .blue) {
                            controller.sendKey("KEYCODE_VOLUME_DOWN")
                        }
                        SidebarIconButton(icon: "camera.fill", color: .purple) {
                            controller.takeScreenshot()
                        }
                        SidebarIconButton(icon: controller.isPhysicalScreenOff ? "eye.slash.fill" : "eye.fill", color: .yellow) {
                            controller.togglePhysicalScreen()
                        }
                    }
                    
                    Divider().background(Color.white.opacity(0.2))
                    
                    Group {
                        SidebarIconButton(icon: "bell.fill", color: .orange) {
                            controller.sendKey("KEYCODE_NOTIFICATION")
                        }
                        SidebarIconButton(icon: "doc.on.clipboard.fill", color: .teal) {
                            controller.syncClipboardToPhone()
                        }
                        SidebarIconButton(icon: "chevron.left", color: .gray) {
                            controller.sendKey("KEYCODE_BACK")
                        }
                        SidebarIconButton(icon: "square.grid.2x2.fill", color: .gray) {
                            controller.sendKey("KEYCODE_APP_SWITCH")
                        }
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 20)
            }
            .padding(24)
        }
        .frame(width: 480, height: 840)
    }
}

// MARK: - Side Toolbar Button
struct SidebarIconButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(color.opacity(0.6), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Frosted Visual Effect View
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
