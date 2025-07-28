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
    private var samplesFromMic: [Float] = []
    @Published var samples: [Int] = []
    @Published var recordingURL: URL?
    @Published var waitingForSamples = false
    
    func requestPermission() {
        audioSession.requestRecordPermission { granted in
            if granted {
                L.a0.debug("Microphone permission granted")
            } else {
                L.a0.error("Microphone permission denied")
            }
        }
    }
    
    func startRecording() {
        // Check permissions first
        let permissionStatus = audioSession.recordPermission
        L.a0.debug("AudioRecorder: Current permission status: \(permissionStatus.rawValue)")
        
        guard permissionStatus == .granted else {
            L.a0.error("AudioRecorder: Recording permission not granted")
            return
        }
        
        let tmpPath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let audioFilename = tmpPath.appendingPathComponent("a0-own-recordings").appendingPathComponent("\(UUID().uuidString).m4a")
        try? FileManager.default.createDirectory(at: audioFilename.deletingLastPathComponent(), withIntermediateDirectories: true)
        recordingURL = audioFilename
        
        L.a0.debug("AudioRecorder.startRecording() to: \(audioFilename)")
        
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
            audioRecorder?.isMeteringEnabled = true // Enable metering for getting audio levels
            audioRecorder?.record()
            isRecording = true
            samplesFromMic = []
            samples = [] // Reset samples
            L.a0.debug("Recording started")
        } catch {
            L.a0.error("Failed to start recording: \(error.localizedDescription) - \(audioFilename)")
        }
    }
    
    func stopRecording() {
        L.a0.debug("AudioRecorder.stopRecording()")
        Task { @MainActor in
            waitingForSamples = true
            isRecording = false
        }
        guard let recorder = audioRecorder else { return }
        
        if recordingURL != nil {
            Task.detached(priority: .userInitiated) {
                let currentTime = recorder.currentTime
                L.a0.debug("Recorded time: \(currentTime.description)")
                recorder.stop()
                
                let samples: [Int] = samplesFromMicToFullIntegers(self.samplesFromMic, limit: DEFAULT_SAMPLE_COUNT)
                
                Task { @MainActor in
                    withAnimation {
                        self.duration = currentTime
                        self.waitingForSamples = false
                        self.samples = samples
                        
                        
                        L.a0.debug("Recording stopped - Duration: \(self.duration) seconds")
                        L.a0.debug("Recording stopped - Samples: \(samples)")
                    }
                    L.a0.debug("self.audioSession.setActive(false)")
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
    
    func updateWaveform() {
        guard isRecording, let recorder = audioRecorder else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0) // Returns dB, typically -160 to 0
        
        // Better conversion for voice recordings: clamp and normalize the dB range
        let clampedPower = max(power, -60.0) // Clamp at -60dB (very quiet)
        let normalizedValue = (clampedPower + 60.0) / 60.0 // Map -60dB to 0dB -> 0.0 to 1.0
        
        samplesFromMic.append(normalizedValue)
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
    var maxAmplitude: Float = 0
    
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
        maxAmplitude = max(maxAmplitude, combinedValue)
    }
    
    // Normalize to integers 0-100 optimized for voice recordings
    let normalizedSamples = processedSamples.map { sample in
        guard maxAmplitude > 0 else { return 0 }
        // Normalize to 0-1 range first
        let normalized = sample / maxAmplitude
        // Use gentler power scaling for natural voice dynamics
        let powerScaled = pow(normalized, 0.75) // Less aggressive expansion
        // Apply conservative scaling to preserve natural dynamics
        let scaled = max(powerScaled * 0.85, normalized * 0.15) // 0.85x scaling with 0.15x minimum
        return min(Int(scaled * 100), 100) // Convert to Int 0-100 range
    }
    
    return normalizedSamples
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
        .background(theme.background)
        .onAppear {
            recorder.requestPermission()
        }
        .onReceive(timer) { _ in
            if recorder.isRecording, let recordingSince = recorder.recordingSince, recordingSince.timeIntervalSince(Date()) < -50 {
                    withAnimation {
                        isTooLong = true
                    }
            }
            if recorder.isRecording {
                recorder.updateWaveform()
            }
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
