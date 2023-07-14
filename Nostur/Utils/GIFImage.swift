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

     /// Initializes the view with the given GIF image data.
     public init(data: Data) {
         self.source = .data(data)
     }

     /// Initialzies the view with the given GIF image url.
     public init(url: URL) {
         self.source = .url(url)
     }

     /// Initialzies the view with the given GIF image name.
     public init(imageName: String) {
         self.source = .imageName(imageName)
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
         _GIFImage(source: source, loopCount: loopCount, isResizable: isResizable)
     }
 }

 @available(iOS 13, tvOS 13, *)
 private struct _GIFImage: UIViewRepresentable {
     let source: GIFSource
     let loopCount: Int
     let isResizable: Bool
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
                 imageView.startAnimatingGIF()
             }
             .store(in: &context.coordinator.subscriptions)
         return imageView
     }

     func updateUIView(_ imageView: GIFImageView, context: Context) {
         switch source {
         case .data(let data):
             imageView.animate(withGIFData: data, loopCount: loopCount)
         case .url(let url):
             imageView.animate(withGIFURL: url, loopCount: loopCount)
         case .imageName(let imageName):
             imageView.animate(withGIFNamed: imageName, loopCount: loopCount)
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
