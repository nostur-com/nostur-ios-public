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
    @Published var samples: [Int] = []
    @Published var recordingURL: URL?
    @Published var waitingForSamples = false
    
    func requestPermission() {
        audioSession.requestRecordPermission { granted in
            if granted {
                L.a1.debug("Microphone permission granted")
            } else {
                L.a1.error("Microphone permission denied")
            }
        }
    }
    
    func startRecording() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("NIP-A1-\(UUID().uuidString).m4a")
        recordingURL = audioFilename
        
        L.a1.debug("AudioRecorder.startRecording() to: \(audioFilename)")
        
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
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.isMeteringEnabled = true // Enable metering for getting audio levels
            audioRecorder?.record()
            isRecording = true
            samples = [] // Reset samples
            L.a1.debug("Recording started")
        } catch {
            L.a1.error("Failed to start recording: \(error.localizedDescription) - \(audioFilename)")
        }
    }
    
    func stopRecording() {
        L.a1.debug("AudioRecorder.stopRecording()")
        Task { @MainActor in
            waitingForSamples = true
            isRecording = false
        }
        guard let recorder = audioRecorder else { return }
        
        if let recordingURL {
            Task.detached(priority: .userInitiated) {
                let currentTime = recorder.currentTime
                L.a1.debug("Recorded time: \(currentTime.description)")
                recorder.stop()
                
                let samples = (try? await loadAudioSamples(from: recordingURL)) ?? []
                
                Task { @MainActor in
                    withAnimation {
                        self.duration = currentTime
                        self.waitingForSamples = false
                        self.samples = samples
                        
                        
                        L.a1.debug("Recording stopped - Duration: \(self.duration) seconds")
                        L.a1.debug("Recording stopped - Samples: \(samples)")
                    }
                    L.a1.debug("self.audioSession.setActive(false)")
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
        let power = recorder.averagePower(forChannel: 0)
        // Convert decibels to linear scale and append to samples
        let normalizedValue = pow(10, power / 20)
        
        
        samples.append(Int(normalizedValue * 100))
    }
}

struct AudioRecorderContentView: View {
    @Environment(\.theme) private var theme
    @StateObject private var recorder = AudioRecorder()
    private var vm: NewPostModel
    @ObservedObject var typingTextModel: TypingTextModel
    @State var isTooLong = false
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
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
                    
                    VoiceMessagePlayer(fileURL: recordingURL, samples: recorder.samples)
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
            if recorder.isRecording, let recordingSince = recorder.recordingSince, recordingSince.timeIntervalSince(Date()) < -3 {
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
