// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import SwiftUI
import Gifu
import Combine

public struct GIFImage: View {
     private let source: GIFSource
     private var loopCount:Int = 0
     private var isResizable = false
    @Binding var isPlaying:Bool

     /// Initializes the view with the given GIF image data.
    public init(data: Data, isPlaying:Binding<Bool>) {
         self.source = .data(data)
        _isPlaying = isPlaying
     }

     /// Sets the desired number of loops. By default, the number of loops infinite.
     public func loopCount(_ value: Int) -> GIFImage {
         var copy = self
         copy.loopCount = value
         return copy
     }

     /// Sets an image to fit its space.
     public func resizable() -> GIFImage {
         var copy = self
         copy.isResizable = true
         return copy
     }

     public var body: some View {
         _GIFImage(source: source, loopCount: loopCount, isResizable: isResizable, isPlaying: $isPlaying)
     }
 }

 @available(iOS 13, tvOS 13, *)
 private struct _GIFImage: UIViewRepresentable {
     let source: GIFSource
     let loopCount: Int
     let isResizable: Bool
     @Binding var isPlaying:Bool
     var subscriptions = Set<AnyCancellable>()

     func makeUIView(context: Context) -> GIFImageView {
         let imageView = GIFImageView()
         if isResizable {
             imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
             imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
         }
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
             imageView.prepareForAnimation(withGIFData: data, loopCount: loopCount)
         case .url(let url):
             imageView.prepareForAnimation(withGIFURL: url, loopCount: loopCount)
         case .imageName(let imageName):
             imageView.prepareForAnimation(withGIFNamed: imageName, loopCount: loopCount)
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

     static func dismantleUIView(_ imageView: GIFImageView, coordinator: ()) {
         imageView.prepareForReuse()
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
