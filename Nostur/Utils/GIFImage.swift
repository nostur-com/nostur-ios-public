// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import SwiftUI
import Gifu
import Combine

public struct GIFImage: View {
    private let source: GIFSource
    @Binding var isPlaying: Bool

     /// Initializes the view with the given GIF image data.
    public init(data: Data, isPlaying: Binding<Bool>) {
         self.source = .data(data)
        _isPlaying = isPlaying
     }
    
     public var body: some View {
         _GIFImage(source: source, isPlaying: $isPlaying)
     }
 }

 @available(iOS 13, tvOS 13, *)
 private struct _GIFImage: UIViewRepresentable {
     let source: GIFSource
     @Binding var isPlaying: Bool

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
         
         switch source {
         case .data(let data):
             imageView.prepareForAnimation(withGIFData: data, loopCount: 0)
         case .url(let url):
             imageView.prepareForAnimation(withGIFURL: url, loopCount: 0)
         case .imageName(let imageName):
             imageView.prepareForAnimation(withGIFNamed: imageName, loopCount: 0)
         }
         
         return imageView
     }

     func updateUIView(_ imageView: GIFImageView, context: Context) {
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
         var subscriptions = Set<AnyCancellable>()
     }
     
     func makeCoordinator() -> Coordinator {
         Coordinator()
     }
 }

 private enum GIFSource {
     case data(Data)
     case url(URL)
     case imageName(String)
 }
