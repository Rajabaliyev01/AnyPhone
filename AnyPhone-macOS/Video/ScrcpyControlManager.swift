import Foundation
import Network

public class ScrcpyControlManager {
    public static let shared = ScrcpyControlManager()
    
    private var serverProcess: Process?
    private var videoConnection: NWConnection?
    private var controlConnection: NWConnection?
    private var isConnected = false
    private let port: UInt16 = 27183
    
    public func ensureControlService(adbPath: String, serial: String) {
        guard !isConnected else { return }
        
        let target = serial.isEmpty ? "" : "-s \(serial)"
        // Setup forward
        let fwdTask = Process()
        fwdTask.executableURL = URL(fileURLWithPath: "/bin/sh")
        fwdTask.arguments = ["-c", "\(adbPath) \(target) forward tcp:\(port) localabstract:scrcpy"]
        try? fwdTask.run()
        fwdTask.waitUntilExit()
        
        // Push server if needed
        let pushTask = Process()
        pushTask.executableURL = URL(fileURLWithPath: "/bin/sh")
        pushTask.arguments = ["-c", "\(adbPath) \(target) push /Applications/QtScrcpy.app/Contents/MacOS/scrcpy-server /data/local/tmp/scrcpy-server.jar"]
        try? pushTask.run()
        pushTask.waitUntilExit()
        
        // Start server in background
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/bin/sh")
        server.arguments = ["-c", "\(adbPath) \(target) shell CLASSPATH=/data/local/tmp/scrcpy-server.jar app_process / com.genymobile.scrcpy.Server 4.1 tunnel_forward=true audio=false"]
        self.serverProcess = server
        try? server.run()
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.connectSockets()
        }
    }
    
    private func connectSockets() {
        let host = NWEndpoint.Host("127.0.0.1")
        let nwPort = NWEndpoint.Port(rawValue: self.port)!
        
        // 1. Video socket (absorbs video handshake)
        let vConn = NWConnection(host: host, port: nwPort, using: .tcp)
        vConn.stateUpdateHandler = { state in
            if case .ready = state {
                // Read dummy byte & header
                vConn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { _, _, _, _ in }
            }
        }
        vConn.start(queue: .global())
        self.videoConnection = vConn
        
        // 2. Control socket
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [weak self] in
            let cConn = NWConnection(host: host, port: nwPort, using: .tcp)
            cConn.stateUpdateHandler = { [weak self] state in
                if case .ready = state {
                    self?.isConnected = true
                    print("[ScrcpyControlManager] Control socket connected successfully!")
                }
            }
            cConn.start(queue: .global())
            self?.controlConnection = cConn
        }
    }
    
    public func setScreenPowerMode(off: Bool) {
        guard isConnected, let conn = controlConnection else {
            return
        }
        let mode: UInt8 = off ? 0 : 2
        let payload = Data([10, mode])
        conn.send(content: payload, completion: .contentProcessed({ error in
            if let error = error {
                print("[ScrcpyControlManager] Error sending screen power mode: \(error)")
            } else {
                print("[ScrcpyControlManager] Successfully set screen power mode to: \(mode)")
            }
        }))
    }
}
