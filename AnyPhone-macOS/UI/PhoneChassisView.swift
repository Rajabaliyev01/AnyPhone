import SwiftUI
import AppKit
import AVFoundation

// MARK: - Native Metal / VideoToolbox Stream View
struct HardwareVideoView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        
        let player = H264StreamPlayer.shared
        player.sampleBufferLayer.frame = view.bounds
        player.sampleBufferLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        player.sampleBufferLayer.cornerRadius = 34
        player.sampleBufferLayer.masksToBounds = true
        
        view.layer?.addSublayer(player.sampleBufferLayer)
        player.startStream()
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let layer = nsView.layer?.sublayers?.first as? AVSampleBufferDisplayLayer {
            layer.frame = nsView.bounds
        }
    }
}

// MARK: - Controller (Touch & Phone Actions)
class EngineController: ObservableObject {
    static let shared = EngineController()
    
    @Published var dialNumber: String = ""
    @Published var isPhysicalScreenOff: Bool = false
    
    var adbPath: String {
        let qtAdb = "/Applications/QtScrcpy.app/Contents/MacOS/adb"
        if FileManager.default.fileExists(atPath: qtAdb) {
            return qtAdb
        }
        return NSString(string: "~/phone_mirror/platform-tools/adb").expandingTildeInPath
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
        runAdb("shell input swipe \(startX) \(startY) \(endX) \(endY) 120")
    }
    
    func takeScreenshot() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dest = NSString(string: "~/Downloads/AnyPhone_\(formatter.string(from: Date())).png").expandingTildeInPath
        runAdb("exec-out screencap -p > \"\(dest)\"")
    }
    
    func togglePhysicalScreen() {
        isPhysicalScreenOff.toggle()
        if isPhysicalScreenOff {
            // Samsung screen off: set minimum brightness and short timeout
            runAdb("shell settings put system screen_brightness 0")
            runAdb("shell settings put system screen_off_timeout 600000")
        } else {
            runAdb("shell settings put system screen_brightness 128")
        }
    }
    
    func sendKey(_ key: String) {
        runAdb("shell input keyevent \(key)")
    }
    
    func callNumber(_ num: String) {
        guard !num.isEmpty else { return }
        let clean = num.replacingOccurrences(of: "#", with: "%23")
        runAdb("shell am start -a android.intent.action.CALL -d tel:\(clean)")
    }
    
    func endCall() {
        runAdb("shell input keyevent KEYCODE_ENDCALL")
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
            task.arguments = ["-c", "\(self.adbPath) \(cmd)"]
            try? task.run()
        }
    }
}

// MARK: - Main Phone Chassis View
struct PhoneChassisView: View {
    @StateObject private var controller = EngineController.shared
    @State private var selectedTab = 0 // 0: Screen Mirror, 1: Dialer
    @State private var dragStart: CGPoint? = nil
    
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
                    
                    // Display Area
                    ZStack {
                        if selectedTab == 0 {
                            // 100% Native VideoToolbox H.264 Hardware Stream
                            HardwareVideoView()
                                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { val in
                                            if dragStart == nil {
                                                dragStart = val.startLocation
                                            }
                                        }
                                        .onEnded { val in
                                            let w: CGFloat = 352
                                            let h: CGFloat = 768
                                            if let start = dragStart {
                                                let dist = hypot(val.location.x - start.x, val.location.y - start.y)
                                                if dist < 8 {
                                                    // Quick Tap
                                                    let rx = max(0, min(1, val.location.x / w))
                                                    let ry = max(0, min(1, val.location.y / h))
                                                    controller.sendTap(xRatio: rx, yRatio: ry)
                                                } else {
                                                    // Swipe
                                                    let sx = max(0, min(1, start.x / w))
                                                    let sy = max(0, min(1, start.y / h))
                                                    let ex = max(0, min(1, val.location.x / w))
                                                    let ey = max(0, min(1, val.location.y / h))
                                                    controller.sendSwipe(fromX: sx, fromY: sy, toX: ex, toY: ey)
                                                }
                                            }
                                            dragStart = nil
                                        }
                                )
                        } else {
                            // Phone Dialer View
                            DialerView(controller: controller)
                                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                        }
                        
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
                    }
                    .frame(width: 352, height: 768)
                }
                
                // MARK: - Quick Action HUD Sidebar
                VStack(spacing: 12) {
                    Group {
                        // Switch between Mirror & Dialpad
                        SidebarIconButton(icon: selectedTab == 0 ? "phone.fill" : "iphone", color: .green) {
                            selectedTab = (selectedTab == 0 ? 1 : 0)
                        }
                        
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

// MARK: - Dialer View
struct DialerView: View {
    @ObservedObject var controller: EngineController
    
    let buttons = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["*", "0", "#"]
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 48)
            
            Text("AnyPhone Dialer")
                .font(.headline)
                .foregroundColor(.white.opacity(0.8))
            
            Text(controller.dialNumber.isEmpty ? "Raqamni tering" : controller.dialNumber)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 24)
                .frame(height: 40)
            
            Spacer()
            
            VStack(spacing: 14) {
                ForEach(buttons, id: \.self) { row in
                    HStack(spacing: 24) {
                        ForEach(row, id: \.self) { item in
                            Button(action: {
                                controller.dialNumber.append(item)
                            }) {
                                Text(item)
                                    .font(.system(size: 24, weight: .medium, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(width: 68, height: 68)
                                    .background(Color(white: 0.2))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            
            Spacer()
            
            HStack(spacing: 36) {
                Button(action: {
                    if !controller.dialNumber.isEmpty {
                        controller.dialNumber.removeLast()
                    }
                }) {
                    Image(systemName: "delete.left.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                        .frame(width: 50, height: 50)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    controller.callNumber(controller.dialNumber)
                }) {
                    Image(systemName: "phone.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .frame(width: 68, height: 68)
                        .background(Color.green)
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    controller.endCall()
                }) {
                    Image(systemName: "phone.down.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                        .frame(width: 50, height: 50)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.08))
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
