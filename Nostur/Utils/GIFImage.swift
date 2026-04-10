// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import SwiftUI
import Gifu
import Combine
import ImageIO

public struct GIFImage: View {
    private let source: GIFSource
    @Binding var isPlaying: Bool
    @State private var replayToken = 0
    @State private var hasReachedLoopLimit = false
    @State private var stopTask: Task<Void, Never>?

     /// Initializes the view with the given GIF image data.
    public init(data: Data, isPlaying: Binding<Bool>) {
         self.source = .data(data)
        _isPlaying = isPlaying
     }
    
     public var body: some View {
         _GIFImage(source: source, isPlaying: .constant(isPlaying && !hasReachedLoopLimit), replayToken: replayToken)
             .contentShape(Rectangle())
             .onAppear {
                 scheduleLoopLimitStop()
             }
             .onChange(of: isPlaying) { newValue in
                 if newValue {
                     hasReachedLoopLimit = false
                     scheduleLoopLimitStop()
                 }
                 else {
                     stopTask?.cancel()
                     stopTask = nil
                 }
             }
             .onDisappear {
                 stopTask?.cancel()
                 stopTask = nil
             }
             .modifier(GIFReplayModifier(isStopped: hasReachedLoopLimit) {
                 restartPlayback()
             })
     }
     
     private func restartPlayback() {
         hasReachedLoopLimit = false
         replayToken += 1
         scheduleLoopLimitStop()
     }
     
     private func scheduleLoopLimitStop() {
         stopTask?.cancel()
         guard isPlaying else { return }
         
         let duration = source.animationDuration * 5.0
         stopTask = Task { @MainActor in
             try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
             guard !Task.isCancelled else { return }
             hasReachedLoopLimit = true
         }
     }
 }

 @available(iOS 13, tvOS 13, *)
 private struct _GIFImage: UIViewRepresentable {
     private let maxLoopCount = 5
     let source: GIFSource
     @Binding var isPlaying: Bool
     let replayToken: Int

     func makeUIView(context: Context) -> GIFImageView {
         let imageView = GIFImageView()
         imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
         imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
         imageView.isUserInteractionEnabled = false // Disable user interaction at UIKit level
         
         receiveNotification(.scenePhaseBackground)
             .receive(on: RunLoop.main)
             .sink { _ in
                 imageView.stopAnimatingGIF()
             }
             .store(in: &context.coordinator.subscriptions)
         receiveNotification(.scenePhaseActive)
             .receive(on: RunLoop.main)
             .sink { _ in
                 guard isPlaying else { return }
                 imageView.startAnimatingGIF()
             }
             .store(in: &context.coordinator.subscriptions)
         
         configureAnimation(for: imageView)
         
         return imageView
     }

     func updateUIView(_ imageView: GIFImageView, context: Context) {
         if replayToken != context.coordinator.lastReplayToken {
             context.coordinator.lastReplayToken = replayToken
             replayAnimation(for: imageView)
             return
         }
         
         if isPlaying {
             imageView.startAnimatingGIF()
         }
         else {
             imageView.stopAnimatingGIF()
         }
     }

     static func dismantleUIView(_ imageView: GIFImageView, coordinator: Coordinator) {
         imageView.prepareForReuse()
         coordinator.subscriptions.removeAll()
     }
     
     class Coordinator: NSObject {
         var lastReplayToken = 0
         var subscriptions = Set<AnyCancellable>()
     }
     
     func makeCoordinator() -> Coordinator {
         Coordinator()
     }
     
     private func configureAnimation(for imageView: GIFImageView) {
         switch source {
         case .data(let data):
             imageView.prepareForAnimation(withGIFData: data, loopCount: maxLoopCount)
         case .url(let url):
             imageView.prepareForAnimation(withGIFURL: url, loopCount: maxLoopCount)
         case .imageName(let imageName):
             imageView.prepareForAnimation(withGIFNamed: imageName, loopCount: maxLoopCount)
         }
     }
     
     private func replayAnimation(for imageView: GIFImageView) {
         guard isPlaying else { return }
         imageView.prepareForReuse()
         configureAnimation(for: imageView)
         imageView.startAnimatingGIF()
     }
}

struct GIFReplayModifier: ViewModifier {
    let isStopped: Bool
    let restart: () -> Void
    
    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content.onHover { isHovering in
            guard isStopped, isHovering else { return }
            restart()
        }
        #else
        content.highPriorityGesture(
            TapGesture().onEnded {
                guard isStopped else { return }
                restart()
            },
            including: isStopped ? .gesture : .subviews
        )
        #endif
    }
}

 private enum GIFSource {
     case data(Data)
     case url(URL)
     case imageName(String)
 }

private extension GIFSource {
    var animationDuration: TimeInterval {
        guard let source = cgImageSource else { return 1.0 }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { return 1.0 }
        
        var totalDuration: TimeInterval = 0
        for index in 0..<frameCount {
            totalDuration += gifFrameDuration(source: source, index: index)
        }
        return max(totalDuration, 0.1)
    }
    
    private var cgImageSource: CGImageSource? {
        switch self {
        case .data(let data):
            return CGImageSourceCreateWithData(data as CFData, nil)
        case .url(let url):
            return CGImageSourceCreateWithURL(url as CFURL, nil)
        case .imageName(let imageName):
            guard let imageURL = Bundle.main.url(forResource: imageName, withExtension: "gif") else { return nil }
            return CGImageSourceCreateWithURL(imageURL as CFURL, nil)
        }
    }
}

private func gifFrameDuration(source: CGImageSource, index: Int) -> TimeInterval {
    guard
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
        let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
    else {
        return 0.1
    }
    
    if let duration = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval, duration > 0 {
        return duration
    }
    if let duration = gifProperties[kCGImagePropertyGIFDelayTime] as? TimeInterval, duration > 0 {
        return duration
    }
    return 0.1
}
