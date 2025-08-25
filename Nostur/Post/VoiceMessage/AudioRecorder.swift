//
//  AudioRecorder.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/07/2025.
//

import SwiftUI
import AVFoundation

public struct VoiceRecording {
    let localFileURL: URL
    let samples: [Int]
    let duration: Int
}

class AudioRecorder: ObservableObject {
    private var audioRecorder: AVAudioRecorder?
    private var audioSession: AVAudioSession = AVAudioSession.sharedInstance()
    @Published var isRecording = false {
        didSet {
            recordingSince = isRecording ? Date() : nil
        }
    }
    @Published var recordingSince: Date? = nil
    @Published var duration: TimeInterval = 0
    private var samplesFromMic: [CGFloat] = []
    @Published var samples: [Int] = []
    @Published var recordingURL: URL?
    @Published var waitingForSamples = false
    
    func requestPermission() {
        audioSession.requestRecordPermission { granted in
#if DEBUG
            if granted {
                L.a0.debug("Microphone permission granted")
            } else {
                L.a0.error("Microphone permission denied")
            }
#endif
        }
    }
    
    func startRecording() {
        // Check permissions first
        let permissionStatus = audioSession.recordPermission
#if DEBUG
        L.a0.debug("AudioRecorder: Current permission status: \(permissionStatus.rawValue)")
#endif
        
        guard permissionStatus == .granted else {
#if DEBUG
            L.a0.error("AudioRecorder: Recording permission not granted")
#endif
            return
        }
        
        let tmpPath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let audioFilename = tmpPath.appendingPathComponent("a0-own-recordings").appendingPathComponent("\(UUID().uuidString).m4a")
        try? FileManager.default.createDirectory(at: audioFilename.deletingLastPathComponent(), withIntermediateDirectories: true)
        recordingURL = audioFilename
        
#if DEBUG
        L.a0.debug("AudioRecorder.startRecording() to: \(audioFilename)")
#endif
        
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
//            AVFormatIDKey: Int(kAudioFormatOpus), // Failed to start recording: The operation couldn’t be completed. (OSStatus error 1718449215.)
            AVSampleRateKey: 24000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ] as [String : Any]
        
        do {
            // Platform-specific audio session configuration
            #if targetEnvironment(macCatalyst)
            // macOS Catalyst needs different audio session setup
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
            L.a0.debug("AudioRecorder: Using macOS Catalyst audio session configuration")
            
//            // Try to set preferred input
//            if let availableInputs = audioSession.availableInputs {
//                L.a0.debug("AudioRecorder: Available inputs: \(availableInputs.map { $0.portName })")
//                for input in availableInputs {
//                    if input.portType == .builtInMic {
//                        try audioSession.setPreferredInput(input)
//                        L.a0.debug("AudioRecorder: Set preferred input to built-in mic: \(input.portName)")
//                        break
//                    }
//                }
//            } else {
//                L.a0.debug("AudioRecorder: No available inputs found")
//            }
            #else
            // iOS configuration
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            L.a0.debug("AudioRecorder: Using iOS audio session configuration")
            #endif
            
            try audioSession.setActive(true)
    
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
//            audioRecorder?.isMeteringEnabled = true // Enable metering for getting audio levels
            audioRecorder?.record()
            isRecording = true
//            samplesFromMic = []
            samples = [] // Reset samples
#if DEBUG
            L.a0.debug("Recording started")
#endif
            
            try self.startMetering()
        } catch {
#if DEBUG
            L.a0.error("Failed to start recording: \(error.localizedDescription) - \(audioFilename)")
#endif
        }
    }
    
    func stopRecording() {
#if DEBUG
        L.a0.debug("AudioRecorder.stopRecording()")
#endif
        self.stopMetering()
        Task { @MainActor in
            waitingForSamples = true
            isRecording = false
        }
        guard let recorder = audioRecorder else { return }
        
        if recordingURL != nil {
            Task.detached(priority: .userInitiated) {
                let currentTime = recorder.currentTime
#if DEBUG
                L.a0.debug("Recorded time: \(currentTime.description)")
#endif
                recorder.stop()
                
//                let samples: [Int] = samplesFromMicToFullIntegers(self.samplesFromMic, limit: DEFAULT_SAMPLE_COUNT)
//                let samples: [Int] = samplesFromMicToFullIntegers(self.envelope, limit: DEFAULT_SAMPLE_COUNT)
                let samples: [Int] = resampleEnvelope(self.samplesFromMic, targetCount: 300)
                
                Task { @MainActor in
                    withAnimation {
                        self.duration = currentTime
                        self.waitingForSamples = false
                        self.samples = samples
                        
                        
#if DEBUG
                        L.a0.debug("Recording stopped - Duration: \(self.duration) seconds")
                        L.a0.debug("Recording stopped - Samples: \(samples)")
#endif
                    }
#if DEBUG
                    L.a0.debug("self.audioSession.setActive(false)")
#endif
                    try? self.audioSession.setActive(false)
                }
            }
        }
    }
    
    func resetRecording() {
        Task { @MainActor in
            recordingURL = nil
            waitingForSamples = false
            recordingSince = nil
            duration = 0
            samplesFromMic = []
            samples = []
        }
        
        // Clean up downloaded file
        guard let recordingURL else { return }
        Task.detached(priority: .medium) {
            try? FileManager.default.removeItem(at: recordingURL)
        }
    }
    
    @Published var waveformData: [CGFloat] = []
    @Published var bars: [CGFloat] = []
    
    @Published var currentLevel: CGFloat = 0

    
//    func updateWaveform() {
//        guard isRecording, let recorder = audioRecorder else { return }
//        recorder.updateMeters()
//        let power = recorder.averagePower(forChannel: 0) // Returns dB, typically -160 to 0
//        
//        let level = normalizedPowerLevel(from: power)
//        waveformData.append(level)
//        
//        // Better conversion for voice recordings: clamp and normalize the dB range
//        let clampedPower = max(power, -60.0) // Clamp at -60dB (very quiet)
//        let normalizedValue = (clampedPower + 60.0) / 60.0 // Map -60dB to 0dB -> 0.0 to 1.0
//        
//        samplesFromMic.append(normalizedValue)
//        
//        let peakDB  = recorder.peakPower(forChannel: 0)     // [-160, 0]
//        let avgDB   = recorder.averagePower(forChannel: 0)
//
//        func dbToLinear(_ db: Float) -> CGFloat {
//            // map dBFS to 0…1 (silence…full scale)
//            return CGFloat(pow(10.0, db / 20.0))
//        }
//
//        let fast = dbToLinear(peakDB)
//        let slow = dbToLinear(avgDB)
//
//        // fast attack / slow release
//        let attack: CGFloat = 0.5   // bigger = snappier
//        let release: CGFloat = 0.1  // smaller = longer tail
//
//        // keep this outside as state
//        currentLevel = max(attack * fast + (1 - attack) * currentLevel,
//                           release * slow + (1 - release) * currentLevel)
//
//        bars.append(currentLevel)   // drive your UI with this
//    }
    
    func normalizedPowerLevel(from decibels: Float) -> CGFloat {
        if decibels < -80 {
            return 0.0
        }
        let minDb: Float = -80
        return CGFloat((decibels - minDb) / -minDb)
    }
    
    
    private let engine = AVAudioEngine()
    @Published var envelope: [CGFloat] = []

      // tune these
      private let windowSize = 8820          // samples per bar
      private let maxBars = 300             // how many bars to keep

    func startMetering() throws {
//            let session = AVAudioSession.sharedInstance()
//            try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetooth, .defaultToSpeaker])
//            try session.setActive(true)

            let input = engine.inputNode
            let format = input.inputFormat(forBus: 0)

            var carry: [Float] = []

            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self = self, let ch = buffer.floatChannelData else { return }
                let frames = Int(buffer.frameLength)
                let mono = Array(UnsafeBufferPointer(start: ch[0], count: frames))  // assume mono input; if stereo, average channels

                // prepend leftovers from previous buffer
                var data = carry + mono
                var newBars: [CGFloat] = []

                // consume in windows
                while data.count >= self.windowSize {
                    let chunk = data.prefix(self.windowSize)
                    let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))

                    // Convert to decibels
                    var db = 20 * log10(max(rms, 1e-7))   // avoid -inf
                    if !db.isFinite { db = -160 }

                    // Normalize: -60 dB (quiet) → 0, 0 dB (loud) → 1
                    let minDb: Float = -60
                    let clamped = max(db, minDb)
                    let normalized = (clamped - minDb) / -minDb   // 0…1

                    // Optional: apply a power curve to make quiet sounds more visible
                    let visible = pow(normalized, 0.5)  // sqrt for louder-looking bars
                    newBars.append(CGFloat(visible))
                    data.removeFirst(self.windowSize)
                }

                // keep remainder for next callback
                carry = data

                DispatchQueue.main.async {
                    self.samplesFromMic.append(contentsOf: newBars)
                    if self.samplesFromMic.count > self.maxBars {
                        self.samplesFromMic.removeFirst(self.samplesFromMic.count - self.maxBars)
                    }
                }
            }

            try engine.start()
        }

    func stopMetering() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}

struct RecWaveformView: View {
    let samples: [CGFloat]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(samples.indices, id: \.self) { i in
                Capsule()
                    .fill(Color.blue)
                    .frame(width: 2, height: max(2, samples[i] * 100))
            }
        }
    }
}

func samplesFromMicToFullIntegers(_ samples: [Float], limit: Int = 100) -> [Int] {
    // Take samples, normalize them to full integers
    
    // If the number of samples is more than given limit, redistribute the samples to make it fit the limit
    // this function is used somewhere else to render a waveform, lower limit just means a lower resolution
    
    guard !samples.isEmpty else { return [] }
    
    let totalSamples = samples.count
    let samplesPerWindow = max(1, totalSamples / limit)
    var processedSamples: [Float] = []
    processedSamples.reserveCapacity(limit)
    
    // Process samples using peak+RMS windowing for better transient capture
    for windowIndex in 0..<limit {
        let startIndex = windowIndex * samplesPerWindow
        let endIndex = min(startIndex + samplesPerWindow, totalSamples)
        
        guard startIndex < totalSamples else { break }
        
        // Calculate peak and RMS for this window
        var sumSquares: Float = 0
        var peakValue: Float = 0
        let windowSize = endIndex - startIndex
        
        for i in startIndex..<endIndex {
            let sample = abs(samples[i])
            sumSquares += sample * sample
            peakValue = max(peakValue, sample)
        }
        
        let rms = sqrt(sumSquares / Float(windowSize))
        // Combine peak and RMS for better transient detection (70% peak, 30% RMS)
        let combinedValue = (peakValue * 0.7) + (rms * 0.3)
        processedSamples.append(combinedValue)
    }
    
    // Create proper dynamic range for voice recognition
    let normalizedSamples = processedSamples.map { sample in
        // Scale to reasonable range for voice (samples are already 0.0-1.0 from updateWaveform)
        let scaled = sample * 80.0 // Scale to 0-80 range to avoid saturation
        
        // Add minimum threshold to show quiet parts
        let withFloor = max(scaled, sample > 0.05 ? 5.0 : 0.0) // 5% minimum for audible parts
        
        return min(Int(withFloor), 100)
    }
    
    return normalizedSamples
}

func samplesFromMicToFullIntegers(_ samples: [CGFloat], limit: Int = 100) -> [Int] {
    // Take samples, normalize them to full integers
    
    // If the number of samples is more than given limit, redistribute the samples to make it fit the limit
    // this function is used somewhere else to render a waveform, lower limit just means a lower resolution
    
    guard !samples.isEmpty else { return [] }
    
    let totalSamples = samples.count
    let samplesPerWindow = max(1, totalSamples / limit)
    var processedSamples: [CGFloat] = []
    processedSamples.reserveCapacity(limit)
    
    // Process samples using peak+RMS windowing for better transient capture
    for windowIndex in 0..<limit {
        let startIndex = windowIndex * samplesPerWindow
        let endIndex = min(startIndex + samplesPerWindow, totalSamples)
        
        guard startIndex < totalSamples else { break }
        
        // Calculate peak and RMS for this window
        var sumSquares: CGFloat = 0
        var peakValue: CGFloat = 0
        let windowSize = endIndex - startIndex
        
        for i in startIndex..<endIndex {
            let sample = abs(samples[i])
            sumSquares += sample * sample
            peakValue = max(peakValue, sample)
        }
        
        let rms = sqrt(sumSquares / CGFloat(windowSize))
        // Combine peak and RMS for better transient detection (70% peak, 30% RMS)
        let combinedValue = (peakValue * 0.7) + (rms * 0.3)
        processedSamples.append(combinedValue)
    }
    
    // Create proper dynamic range for voice recognition
    let normalizedSamples = processedSamples.map { sample in
        // Scale to reasonable range for voice (samples are already 0.0-1.0 from updateWaveform)
        let scaled = sample * 80.0 // Scale to 0-80 range to avoid saturation
        
        // Add minimum threshold to show quiet parts
        let withFloor = max(scaled, sample > 0.05 ? 5.0 : 0.0) // 5% minimum for audible parts
        
        return min(Int(withFloor), 100)
    }
    
    return normalizedSamples
}

func resampleEnvelope(_ samples: [CGFloat], targetCount: Int) -> [Int] {
    guard !samples.isEmpty, targetCount > 0 else {
        return Array(repeating: 0, count: targetCount)
    }

    let factor = Double(samples.count) / Double(targetCount)

    var result: [Int] = []
    result.reserveCapacity(targetCount)

    for i in 0..<targetCount {
        let start = Int(Double(i) * factor)
        let end   = Int(Double(i + 1) * factor)
        let slice = samples[start ..< min(end, samples.count)]
        
        // Choose AVG or MAX depending on the "look" you want
        let value: CGFloat
        if let maxVal = slice.max() {
            value = maxVal   // punchier, iMessage-like
        } else {
            value = samples[start]
        }

        let scaled = Int((value * 100).rounded())  // 0–100
        result.append(min(max(scaled, 0), 100))
    }

    return result
}


struct AudioRecorderContentView: View {
    @Environment(\.theme) private var theme
    @StateObject private var recorder = AudioRecorder()
    private var vm: NewPostModel
    @ObservedObject var typingTextModel: TypingTextModel
    @State var isTooLong = false
    let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    private var onDismiss: () -> Void
    private var replyTo: ReplyTo? = nil
    
    private var shouldDisablePostButton: Bool {
        (typingTextModel.sending || typingTextModel.uploading || recorder.isRecording || recorder.waitingForSamples || recorder.recordingURL == nil)
    }
    
    init(vm: NewPostModel, replyTo: ReplyTo? = nil, onDismiss: @escaping () -> Void) {
        self.vm = vm
        self.onDismiss = onDismiss
        self.typingTextModel = vm.typingTextModel
        self.replyTo = replyTo
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // FINISHED RECORDING
            if !recorder.isRecording && !recorder.waitingForSamples, let recordingURL = recorder.recordingURL { //, recorder.duration > 0 {
                HStack(spacing: 10) {
                    Button(action: {
                        recorder.resetRecording()
                        isTooLong = false
                    }) {
                        Image(systemName: "multiply")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    VoiceMessagePlayer(url: recordingURL, samples: recorder.samples)
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 10)
            }
            else if recorder.waitingForSamples {
                ProgressView()
                    .padding(.vertical, 20)
            }
            else {
                VStack(spacing: 16) {
                    
                    
                    
                    // RECORDING TIMER
                    if recorder.isRecording, let recordingSince = recorder.recordingSince {
                        Text("\(recordingSince, style: .timer)")
                            .monospacedDigit()
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red)
                            .cornerRadius(12)
                    }
                    
                    // WARNING MESSAGE
                    if isTooLong {
                        Text("Keep your message short")
                            .font(.caption)
                            .foregroundColor(theme.accent)
                            .padding(.horizontal, 16)
                    }
                    
                    // RECORD BUTTON
                    RecordButton {
                        isTooLong = false
                        recorder.startRecording()
                    } stopAction: {
                        recorder.stopRecording()
                    }
                    .frame(width: 90, height: 90)
                    .padding(.horizontal, 16)
                }
            }
        }
        .onAppear {
            recorder.requestPermission()
        }
        .onReceive(timer) { _ in
            if recorder.isRecording, let recordingSince = recorder.recordingSince, recordingSince.timeIntervalSince(Date()) < -50 {
                    withAnimation {
                        isTooLong = true
                    }
            }
//            if recorder.isRecording {
//                recorder.updateWaveform()
//            }
        }
        
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button {
                        typingTextModel.sending = true
            
                        // Need to do these here in main thread
                        guard let account = vm.activeAccount, account.isFullAccount else {
                            sendNotification(.anyStatus, ("Problem with account", "NewPost"))
                            return
                        }
                        let isNC = account.isNC
                        let pubkey = account.publicKey
                      
                        guard let localFileURL = recorder.recordingURL else { return }
                        
                        typingTextModel.voiceRecording = VoiceRecording(localFileURL: localFileURL, samples: recorder.samples, duration: Int(recorder.duration))
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { // crash if we don't delay
                            Task {
                                await self.vm.sendNow(isNC: isNC, pubkey: pubkey, account: account, replyTo: replyTo, onDismiss: { onDismiss() })
                            }
                        }
                    } label: {
                        if (typingTextModel.uploading || typingTextModel.sending) {
                            ProgressView().colorInvert()
                        }
                        else {
                            Text("Post.verb", comment: "Button to post (publish) a post")
                        }
                    }
                    .buttonStyle(NRButtonStyle(theme: theme, style: .borderedProminent))
                    .cornerRadius(20)
                    .disabled(shouldDisablePostButton)
                    .opacity(shouldDisablePostButton ? 0.25 : 1.0)
                }
            }
            
            ToolbarItem(placement: .principal) {
                if let uploadError = vm.uploadError {
                    Text(uploadError).foregroundColor(.red)
                }
            }
        }
    }
}

//#Preview("Audio Recorder") {
//    AudioRecorderContentView()
//}
