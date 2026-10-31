import SwiftUI

struct ComposerVideoUploadProgress: View {
    let videos: [PostedVideoMeta]
    let isBusy: Bool
    let isShortVideo: Bool
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        if !videos.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(videos) { video in
                    ComposerVideoUploadRow(video: video, isBusy: isBusy, isShortVideo: isShortVideo, onRetry: onRetry)
                }
                if isBusy {
                    Button("Cancel upload", systemImage: "xmark", action: onCancel)
                }
            }
            .padding(10)
        }
    }
}

private struct ComposerVideoUploadRow: View {
    @ObservedObject var video: PostedVideoMeta
    let isBusy: Bool
    let isShortVideo: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !isShortVideo {
                Picker("Video quality", selection: $video.quality) {
                    Text("Automatic").tag(VideoUploadQuality.automatic)
                    Text("Higher quality").tag(VideoUploadQuality.higher)
                    Text("Smaller file").tag(VideoUploadQuality.smaller)
                }
                .disabled(isBusy)
            }
            switch video.uploadState {
            case .preparing:
                Text("Preparing video…")
                ProgressView(value: video.preparationProgress)
            case .uploading(let percentage):
                Text("Uploading video…")
                ProgressView(value: Double(percentage ?? 0), total: 100)
            case .waitingForServer, .readingDimensions:
                HStack { ProgressView(); Text("Waiting for media server…") }
            case .processing:
                HStack { ProgressView(); Text("Media server is processing the video…") }
            case .failed(let message):
                Text(message).foregroundStyle(.red)
                HStack {
                    Button("Retry upload", action: onRetry)
                    if video.quality != .smaller {
                        Button("Retry with a smaller video") {
                            video.quality = .smaller
                            onRetry()
                        }
                    }
                }
                .disabled(isBusy)
            case .uploaded:
                Label("Video uploaded", systemImage: "checkmark")
            case .idle:
                if let prepared = video.preparedVideo {
                    Text("Prepared video: \(ByteCountFormatter.string(fromByteCount: prepared.byteCount, countStyle: .file))")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
    }
}
