import Foundation
import AVFoundation

/**
 * AudioController
 * Captures Mac Microphone audio to stream to Android phone.
 * Plays incoming Phone Call PCM audio on Mac speakers / AirPods.
 */
class AudioController: ObservableObject {
    static let shared = AudioController()
    
    private var audioEngine = AVAudioEngine()
    @Published var isMuted: Bool = false
    @Published var isSpeakerOn: Bool = true
    
    func startMicCapture(onAudioData: @escaping (Data) -> Void) {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            // Forward Mac Mic buffer to Android
        }
        try? audioEngine.start()
    }
    
    func stopMicCapture() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
    }
}
