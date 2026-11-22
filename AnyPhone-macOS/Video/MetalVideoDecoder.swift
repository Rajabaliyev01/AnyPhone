import Foundation
import AVFoundation
import VideoToolbox
import AppKit

public class H264StreamPlayer: NSObject, ObservableObject {
    public static let shared = H264StreamPlayer()
    
    public let sampleBufferLayer = AVSampleBufferDisplayLayer()
    private var process: Process?
    private var inputPipe: Pipe?
    private var isRunning = false
    
    private var formatDesc: CMVideoFormatDescription?
    private var sps: [UInt8]?
    private var pps: [UInt8]?
    private var buffer = Data()
    
    public override init() {
        super.init()
        sampleBufferLayer.videoGravity = .resizeAspectFill
        sampleBufferLayer.backgroundColor = NSColor.black.cgColor
    }
    
    public func startStream(serial: String? = nil) {
        guard !isRunning else { return }
        isRunning = true
        buffer.removeAll()
        
        let adbPath = "/Applications/QtScrcpy.app/Contents/MacOS/adb"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: adbPath)
        
        var args: [String] = []
        if let s = serial, !s.isEmpty {
            args += ["-s", s]
        }
        
        // 60 FPS, optimized 720x1560 resolution with 6Mbps for ultra-smooth Wi-Fi & USB
        args += [
            "shell",
            "screenrecord",
            "--output-format=h264",
            "--size", "720x1560",
            "--bit-rate", "6000000",
            "--time-limit", "0",
            "-"
        ]
        proc.arguments = args
        
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.processIncomingChunk(chunk)
        }
        
        self.process = proc
        self.inputPipe = pipe
        
        do {
            try proc.run()
            print("[AnyPhone] H.264 Stream started successfully! Target: \(serial ?? "auto")")
        } catch {
            print("[AnyPhone] Failed to start stream: \(error)")
        }
    }
    
    public func stopStream() {
        isRunning = false
        inputPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        inputPipe = nil
    }
    
    public func restartStream(serial: String? = nil) {
        stopStream()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.startStream(serial: serial)
        }
    }
    
    private func processIncomingChunk(_ chunk: Data) {
        buffer.append(chunk)
        
        // Find Annex-B NAL start codes (0x00 0x00 0x00 0x01 or 0x00 0x00 0x01)
        while true {
            let bytes = [UInt8](buffer)
            guard bytes.count > 4 else { break }
            
            var firstStart = -1
            var secondStart = -1
            var firstPrefixLen = 0
            
            var i = 0
            while i < bytes.count - 3 {
                if bytes[i] == 0 && bytes[i+1] == 0 {
                    if bytes[i+2] == 1 {
                        if firstStart == -1 {
                            firstStart = i
                            firstPrefixLen = 3
                            i += 3
                            continue
                        } else {
                            secondStart = i
                            break
                        }
                    } else if i < bytes.count - 4 && bytes[i+2] == 0 && bytes[i+3] == 1 {
                        if firstStart == -1 {
                            firstStart = i
                            firstPrefixLen = 4
                            i += 4
                            continue
                        } else {
                            secondStart = i
                            break
                        }
                    }
                }
                i += 1
            }
            
            if firstStart != -1 && secondStart != -1 {
                let naluData = buffer.subdata(in: (firstStart + firstPrefixLen)..<secondStart)
                buffer.removeSubrange(0..<secondStart)
                handleNALU(naluData)
            } else {
                break
            }
        }
    }
    
    private func handleNALU(_ naluData: Data) {
        guard !naluData.isEmpty else { return }
        let bytes = [UInt8](naluData)
        let naluType = bytes[0] & 0x1F
        
        if naluType == 7 { // SPS
            self.sps = bytes
            return
        } else if naluType == 8 { // PPS
            self.pps = bytes
            createFormatDescription()
            return
        }
        
        guard let formatDesc = self.formatDesc else { return }
        
        // Convert to AVCC format
        var length = UInt32(naluData.count).bigEndian
        var blockBuffer: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: 4 + naluData.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: 4 + naluData.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == kCMBlockBufferNoErr, let block = blockBuffer else { return }
        
        withUnsafeBytes(of: &length) { lenPtr in
            CMBlockBufferReplaceDataBytes(
                with: lenPtr.baseAddress!,
                blockBuffer: block,
                offsetIntoDestination: 0,
                dataLength: 4
            )
        }
        
        naluData.withUnsafeBytes { dataPtr in
            CMBlockBufferReplaceDataBytes(
                with: dataPtr.baseAddress!,
                blockBuffer: block,
                offsetIntoDestination: 4,
                dataLength: naluData.count
            )
        }
        
        var sampleBuffer: CMSampleBuffer?
        var sampleTiming = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        
        let createStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: formatDesc,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &sampleTiming,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        
        if createStatus == noErr, let sb = sampleBuffer {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.sampleBufferLayer.sampleBufferRenderer.enqueue(sb)
            }
        }
    }
    
    private func createFormatDescription() {
        guard let s = self.sps, let p = self.pps else { return }
        s.withUnsafeBytes { spsPtr in
            p.withUnsafeBytes { ppsPtr in
                let pointers = [
                    spsPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    ppsPtr.baseAddress!.assumingMemoryBound(to: UInt8.self)
                ]
                let sizes = [s.count, p.count]
                let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: pointers,
                    parameterSetSizes: sizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &self.formatDesc
                )
                if status == noErr {
                    print("[AnyPhone] Video format description updated.")
                }
            }
        }
    }
}
