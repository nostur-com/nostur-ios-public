//
//  VideoPickerView.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/06/2024.
//

import SwiftUI
import UIKit
import MobileCoreServices
@preconcurrency import AVFoundation

struct VideoPickerView: UIViewControllerRepresentable {
    @Binding var selectedVideoURL: URL?
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        var parent: VideoPickerView

        init(parent: VideoPickerView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let mediaType = info[.mediaType] as? String, mediaType == UTType.movie.identifier {
                if let url = info[.mediaURL] as? URL {
                    parent.selectedVideoURL = url
                }
            }
            picker.dismiss(animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
//        picker.videoExportPreset = "AVAssetExportPresetMediumQuality" // <-- blurry screen recording
//        picker.videoExportPreset = "AVAssetExportPreset1920x1080" // <-- no compression at all for screen recording?? looks like passthrough
//        picker.videoExportPreset = "AVAssetExportPresetHighestQuality"
        picker.delegate = context.coordinator
        picker.mediaTypes = [UTType.movie.identifier]
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
}

func compressVideoAsync(inputURL: URL, outputURL: URL) async -> URL? {
    let asset = AVURLAsset(url: inputURL)

    do {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { return nil }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let transformedSize = naturalSize.applying(preferredTransform)
        let outputSize = CGSize(
            width: abs(transformedSize.width).rounded(),
            height: abs(transformedSize.height).rounded()
        )
        let encodingSize = CGSize(
            width: abs(naturalSize.width).rounded(),
            height: abs(naturalSize.height).rounded()
        )
        guard outputSize.width > 0, outputSize.height > 0,
              encodingSize.width > 0, encodingSize.height > 0 else { return nil }

        try? FileManager.default.removeItem(at: outputURL)

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        writer.metadata = []

        let videoReaderOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        videoReaderOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoReaderOutput) else { return nil }
        reader.add(videoReaderOutput)

        let videoWriterInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoOutputSettings(
                encodingSize: encodingSize,
                displaySize: outputSize,
                framesPerSecond: nominalFrameRate
            )
        )
        videoWriterInput.expectsMediaDataInRealTime = false
        videoWriterInput.transform = preferredTransform
        guard writer.canAdd(videoWriterInput) else { return nil }
        writer.add(videoWriterInput)

        var audioReaderOutput: AVAssetReaderTrackOutput?
        var audioWriterInput: AVAssetWriterInput?
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            let readerOutput = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM
                ]
            )
            let writerInput = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVEncoderBitRateKey: 128_000,
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 2
                ]
            )
            readerOutput.alwaysCopiesSampleData = false
            if reader.canAdd(readerOutput), writer.canAdd(writerInput) {
                reader.add(readerOutput)
                writer.add(writerInput)
                audioReaderOutput = readerOutput
                audioWriterInput = writerInput
            }
        }

        guard writer.startWriting(), reader.startReading() else {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }
        writer.startSession(atSourceTime: .zero)

        let completed = await writeSamples(
            reader: reader,
            writer: writer,
            videoReaderOutput: videoReaderOutput,
            videoWriterInput: videoWriterInput,
            audioReaderOutput: audioReaderOutput,
            audioWriterInput: audioWriterInput
        )
        if completed {
            return outputURL
        }
    } catch {
        L.og.error("Video compression failed: \(error.localizedDescription)")
    }

    try? FileManager.default.removeItem(at: outputURL)
    return nil
}

private func videoOutputSettings(
    encodingSize: CGSize,
    displaySize: CGSize,
    framesPerSecond: Float
) -> [String: Any] {
    let fps = max(Double(framesPerSecond), 30)
    let pixelsPerSecond = Double(displaySize.width * displaySize.height) * min(fps, 60)

    // About 0.10 bits per pixel per frame keeps text in screen recordings sharp.
    // Bound the result so small clips still look good and 4K uploads stay practical.
    let averageBitRate = Int(min(max(pixelsPerSecond * 0.10, 2_500_000), 16_000_000))

    return [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: Int(encodingSize.width),
        AVVideoHeightKey: Int(encodingSize.height),
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: averageBitRate,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoExpectedSourceFrameRateKey: Int(fps.rounded()),
            AVVideoMaxKeyFrameIntervalDurationKey: 2
        ]
    ]
}

private func writeSamples(
    reader: AVAssetReader,
    writer: AVAssetWriter,
    videoReaderOutput: AVAssetReaderTrackOutput,
    videoWriterInput: AVAssetWriterInput,
    audioReaderOutput: AVAssetReaderTrackOutput?,
    audioWriterInput: AVAssetWriterInput?
) async -> Bool {
    await withCheckedContinuation { continuation in
        let group = DispatchGroup()
        let videoQueue = DispatchQueue(label: "com.nostur.video-compression.video")

        group.enter()
        videoWriterInput.requestMediaDataWhenReady(on: videoQueue) {
            while videoWriterInput.isReadyForMoreMediaData {
                guard let sampleBuffer = videoReaderOutput.copyNextSampleBuffer() else {
                    videoWriterInput.markAsFinished()
                    group.leave()
                    return
                }
                if !videoWriterInput.append(sampleBuffer) {
                    reader.cancelReading()
                    videoWriterInput.markAsFinished()
                    group.leave()
                    return
                }
            }
        }

        if let audioReaderOutput, let audioWriterInput {
            let audioQueue = DispatchQueue(label: "com.nostur.video-compression.audio")
            group.enter()
            audioWriterInput.requestMediaDataWhenReady(on: audioQueue) {
                while audioWriterInput.isReadyForMoreMediaData {
                    guard let sampleBuffer = audioReaderOutput.copyNextSampleBuffer() else {
                        audioWriterInput.markAsFinished()
                        group.leave()
                        return
                    }
                    if !audioWriterInput.append(sampleBuffer) {
                        reader.cancelReading()
                        audioWriterInput.markAsFinished()
                        group.leave()
                        return
                    }
                }
            }
        }

        group.notify(queue: videoQueue) {
            guard reader.status == .completed else {
                writer.cancelWriting()
                continuation.resume(returning: false)
                return
            }
            writer.finishWriting {
                continuation.resume(returning: writer.status == .completed)
            }
        }
    }
}
