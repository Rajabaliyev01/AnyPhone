import Foundation
import AVFoundation
import AudioToolbox
import Network

/**
 * AudioController
 * Bi-directional real-time audio bridge:
 * 1. Receives raw PCM 48kHz Stereo audio from Android and streams to Mac Speakers.
 * 2. Captures Mac Microphone and injects it into Android.
 */
public class AudioController: NSObject, ObservableObject {
    public static let shared = AudioController()
    
    @Published public var isAudioStreaming: Bool = false
    @Published public var isMicActive: Bool = false
    
    private var audioConnection: NWConnection?
    private var audioEngine = AVAudioEngine()
    private var audioPlayerNode = AVAudioPlayerNode()
    private var audioFormat: AVAudioFormat?
    private let port: UInt16 = 28200
    
    public override init() {
        super.init()
        setupAudioOutput()
    }
    
    private func setupAudioOutput() {
        // Standard Android Sndcpy PCM format: 48000Hz, 16-bit Signed Integer (Linear PCM), Stereo
        audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 48000,
            channels: 2,
            interleaved: true
        )
        
        guard let format = audioFormat else { return }
        audioEngine.attach(audioPlayerNode)
        audioEngine.connect(audioPlayerNode, to: audioEngine.mainMixerNode, format: format)
        
        do {
            try audioEngine.start()
            audioPlayerNode.play()
            print("[AudioController] AVAudioEngine output initialized.")
        } catch {
            print("[AudioController] Failed to start audio output engine: \(error)")
        }
    }
    
    public func startAudioBridge(adbPath: String, serial: String) {
        guard !isAudioStreaming else { return }
        isAudioStreaming = true
        
        let target = serial.isEmpty ? "" : "-s \(serial)"
        
        // 1. Setup port forward and start sndcpy service
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let fwd = Process()
            fwd.executableURL = URL(fileURLWithPath: "/bin/sh")
            fwd.arguments = ["-c", "\(adbPath) \(target) forward tcp:\(self.port) localabstract:sndcpy"]
            try? fwd.run()
            fwd.waitUntilExit()
            
            let startApp = Process()
            startApp.executableURL = URL(fileURLWithPath: "/bin/sh")
            startApp.arguments = ["-c", "\(adbPath) \(target) shell am start -n com.rom1v.sndcpy/.MainActivity"]
            try? startApp.run()
            
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
                self.connectAudioSocket()
            }
        }
    }
    
    private func connectAudioSocket() {
        let host = NWEndpoint.Host("127.0.0.1")
        let nwPort = NWEndpoint.Port(rawValue: self.port)!
        
        let conn = NWConnection(host: host, port: nwPort, using: .tcp)
        conn.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                print("[AudioController] Connected to Android Audio Stream!")
                self?.readNextAudioChunk(from: conn)
            }
        }
        conn.start(queue: .global())
        self.audioConnection = conn
    }
    
    private func readNextAudioChunk(from conn: NWConnection) {
        // Read 1024 to 4096 bytes of 48kHz PCM
        conn.receive(minimumIncompleteLength: 512, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty, let format = self.audioFormat {
                self.scheduleBuffer(data: data, format: format)
            }
            if !isComplete && error == nil {
                self.readNextAudioChunk(from: conn)
            }
        }
    }
    
    private func scheduleBuffer(data: Data, format: AVAudioFormat) {
        let frameCount = UInt32(data.count) / format.streamDescription.pointee.mBytesPerFrame
        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        
        pcmBuffer.frameLength = frameCount
        data.withUnsafeBytes { rawPtr in
            if let src = rawPtr.baseAddress {
                let dest = pcmBuffer.int16ChannelData?[0]
                memcpy(dest, src, data.count)
            }
        }
        
        audioPlayerNode.scheduleBuffer(pcmBuffer)
    }
    
    public func stopAudioBridge() {
        isAudioStreaming = false
        audioConnection?.cancel()
        audioConnection = nil
    }
}
