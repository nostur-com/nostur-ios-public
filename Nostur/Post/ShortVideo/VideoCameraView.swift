//
//  VideoCameraView.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/03/2026.
//

import SwiftUI
import AVFoundation

struct VideoCameraView: View {
    var maxDuration: Double = 6.0
    var onRecorded: (URL) -> Void
    var onCancel: () -> Void
    
    @StateObject private var recorder = VideoRecorderModel()
    @State private var cameraPosition: AVCaptureDevice.Position = .back
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Camera preview
            VideoCameraPreviewRepresentable(session: recorder.session)
                .ignoresSafeArea()
            
            VStack {
                // Top bar with cancel and flip
                HStack {
                    Button {
                        recorder.stopSession()
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    
                    Spacer()
                    
                    if !recorder.isRecording {
                        Button {
                            cameraPosition = (cameraPosition == .back) ? .front : .back
                            recorder.switchCamera(to: cameraPosition)
                        } label: {
                            Image(systemName: "camera.rotate")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Circle().fill(Color.black.opacity(0.5)))
                        }
                    }
                }
                .padding()
                
                Spacer()
                
                // Countdown timer
                if recorder.isRecording {
                    Text(String(format: "%.1f", max(0, maxDuration - recorder.recordedDuration)))
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .shadow(radius: 4)
                    
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 4)
                            
                            Capsule()
                                .fill(Color.red)
                                .frame(width: geo.size.width * min(1, recorder.recordedDuration / maxDuration), height: 4)
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 8)
                }
                
                // Record button
                Button {
                    if recorder.isRecording {
                        recorder.stopRecording()
                    } else {
                        recorder.startRecording(maxDuration: maxDuration)
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 72, height: 72)
                        
                        if recorder.isRecording {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.red)
                                .frame(width: 28, height: 28)
                        } else {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 60, height: 60)
                        }
                    }
                }
                .padding(.bottom, 40)
                
                if let error = recorder.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                }
            }
        }
        .onAppear {
            recorder.setupSession(position: cameraPosition)
        }
        .onDisappear {
            recorder.stopSession()
        }
        .onChange(of: recorder.recordedVideoURL) { url in
            if let url {
                recorder.stopSession()
                onRecorded(url)
            }
        }
    }
}

// MARK: - Video Recorder Model

class VideoRecorderModel: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private var movieOutput = AVCaptureMovieFileOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var timer: Timer?
    
    @Published var isRecording = false
    @Published var recordedDuration: Double = 0
    @Published var recordedVideoURL: URL?
    @Published var error: String?
    
    func setupSession(position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        
        // Video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            error = "Cannot access camera"
            session.commitConfiguration()
            return
        }
        
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
            currentInput = videoInput
        }
        
        // Audio input
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }
        
        // Movie output
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
            
            // Set video orientation
            if let connection = movieOutput.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
        }
        
        session.commitConfiguration()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }
    
    func switchCamera(to position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        
        // Remove current input
        if let currentInput {
            session.removeInput(currentInput)
        }
        
        // Add new input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            session.commitConfiguration()
            return
        }
        
        if session.canAddInput(videoInput) {
            session.addInput(videoInput)
            currentInput = videoInput
        }
        
        // Update orientation on connection
        if let connection = movieOutput.connection(with: .video),
           connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        
        session.commitConfiguration()
    }
    
    func startRecording(maxDuration: Double) {
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        
        movieOutput.maxRecordedDuration = CMTime(seconds: maxDuration, preferredTimescale: 600)
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        
        DispatchQueue.main.async {
            self.isRecording = true
            self.recordedDuration = 0
        }
        
        // Timer for countdown
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.recordedDuration += 0.1
            }
        }
    }
    
    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
        timer?.invalidate()
        timer = nil
    }
    
    func stopSession() {
        timer?.invalidate()
        timer = nil
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.stopRunning()
        }
    }
}

extension VideoRecorderModel: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        timer?.invalidate()
        timer = nil
        
        DispatchQueue.main.async {
            self.isRecording = false
            if let error {
                // maxRecordedDuration reached is not a real error - the file is still valid
                if (error as NSError).domain == AVFoundationErrorDomain &&
                   (error as NSError).code == AVError.maximumDurationReached.rawValue {
                    self.recordedVideoURL = outputFileURL
                } else {
                    self.error = error.localizedDescription
                }
            } else {
                self.recordedVideoURL = outputFileURL
            }
        }
    }
}

// MARK: - Camera Preview UIViewRepresentable

struct VideoCameraPreviewRepresentable: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> VideoCameraPreviewUIView {
        let view = VideoCameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: VideoCameraPreviewUIView, context: Context) {}
}

class VideoCameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    
    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
