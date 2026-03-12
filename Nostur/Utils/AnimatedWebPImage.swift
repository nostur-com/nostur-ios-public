//
//  AnimatedWebPImage.swift
//  Nostur
//
//  Created by Fabian Lachman on 12/03/2025.
//

import SwiftUI
import ImageIO
import Combine

// Returns true if data is an animated WebP (RIFF/WEBP header + more than one frame via ImageIO)
func isAnimatedWebPData(_ data: Data) -> Bool {
    guard data.count > 12 else { return false }
    // WebP: "RIFF" at 0-3, "WEBP" at 8-11
    guard data[0] == 0x52, data[1] == 0x49, data[2] == 0x46, data[3] == 0x46,  // RIFF
          data[8] == 0x57, data[9] == 0x45, data[10] == 0x42, data[11] == 0x50  // WEBP
    else { return false }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
    return CGImageSourceGetCount(source) > 1
}

// Renders animated WebP data using ImageIO frame extraction, mirroring GIFImage.
public struct AnimatedWebPImage: View {
    private let data: Data
    @Binding var isPlaying: Bool

    public init(data: Data, isPlaying: Binding<Bool>) {
        self.data = data
        _isPlaying = isPlaying
    }

    public var body: some View {
        _AnimatedWebPImage(data: data, isPlaying: $isPlaying)
    }
}

private struct _AnimatedWebPImage: UIViewRepresentable {
    let data: Data
    @Binding var isPlaying: Bool

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.isUserInteractionEnabled = false

        receiveNotification(.scenePhaseBackground)
            .receive(on: RunLoop.main)
            .sink { _ in
                imageView.stopAnimating()
            }
            .store(in: &context.coordinator.subscriptions)
        receiveNotification(.scenePhaseActive)
            .receive(on: RunLoop.main)
            .sink { _ in
                guard isPlaying else { return }
                imageView.startAnimating()
            }
            .store(in: &context.coordinator.subscriptions)

        loadFrames(into: imageView, from: data)
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        if isPlaying {
            if !imageView.isAnimating { imageView.startAnimating() }
        } else {
            imageView.stopAnimating()
        }
    }

    static func dismantleUIView(_ imageView: UIImageView, coordinator: Coordinator) {
        imageView.stopAnimating()
        imageView.animationImages = nil
        coordinator.subscriptions.removeAll()
    }

    class Coordinator: NSObject {
        var subscriptions = Set<AnyCancellable>()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func loadFrames(into imageView: UIImageView, from data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 1 else {
            if let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                imageView.image = UIImage(cgImage: cgImage)
            }
            return
        }

        var frames: [UIImage] = []
        var totalDuration: Double = 0

        for i in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            totalDuration += frameDuration(source: source, index: i)
            frames.append(UIImage(cgImage: cgImage))
        }

        imageView.animationImages = frames
        imageView.animationDuration = totalDuration > 0 ? totalDuration : Double(frameCount) * 0.1
        imageView.animationRepeatCount = 0 // loop forever
    }
}

private func frameDuration(source: CGImageSource, index: Int) -> Double {
    guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
        return 0.1
    }
    if let webpDict = props[kCGImagePropertyWebPDictionary] as? [CFString: Any] {
        if let d = webpDict[kCGImagePropertyWebPUnclampedDelayTime] as? Double, d > 0 { return d }
        if let d = webpDict[kCGImagePropertyWebPDelayTime] as? Double, d > 0 { return d }
    }
    return 0.1
}
