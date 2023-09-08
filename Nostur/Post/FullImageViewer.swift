//
//  FullImageViewer.swift
//  Nostur
//
//  Created by Fabian Lachman on 06/06/2023.
//

import SwiftUI
import Nuke
import NukeUI
//import AVKit
//import AVFoundation

struct FullImageViewer: View {
    @EnvironmentObject var theme:Theme
    @Environment(\.dismiss) var dismiss
    //    @Binding var fullImageIsShown:Bool
    var fullImageURL:URL
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var position: CGSize = .zero
    @State private var newPosition: CGSize = .zero
    @State var isPlaying = true
    @State private var gestureStartTime: Date?
    @State private var sharableImage:UIImage? = nil
    @State private var sharableGif:Data? = nil

    
    var body: some View {
        
        let magnifyAndDragGesture = MagnificationGesture()
            .onChanged { value in
                let delta = value / self.lastScale
                self.lastScale = value
                self.scale *= delta
            }
            .onEnded { value in
                self.lastScale = 1.0
            }
            .simultaneously(with: DragGesture()
                .onChanged { value in
                    self.position.width = self.newPosition.width + value.translation.width
                    self.position.height = self.newPosition.height + value.translation.height
                }
                .onEnded { value in
                    self.newPosition = self.position
                }
            )
            .simultaneously(with: DragGesture(minimumDistance: 3.0, coordinateSpace: .local)
                .onChanged { value in
                    if gestureStartTime == nil {
                        gestureStartTime = Date()
                    }
                }
                .onEnded { value in
                    L.og.debug("FullimageViewer: \(value.translation.debugDescription)")
                    guard let startTime = gestureStartTime else { return }
                                         let duration = Date().timeIntervalSince(startTime)
                                         let quickSwipeThreshold: TimeInterval = 0.25 // Adjust this value as needed
                    L.og.debug("FullimageViewer: \(duration)")
                    switch(value.translation.width, value.translation.height) {
                            //                    case (...0, -30...30):  print("left swipe")
                            //                    case (0..., -30...30):  print("right swipe")
                            //                    case (-100...100, ...0):  print("up swipe")
                        case (-100...100, 0...):
                            if duration < quickSwipeThreshold {
                                dismiss()
                            }
                            else {
                                gestureStartTime = nil
                            }
                        default:
                        L.og.debug("no clue")
                            gestureStartTime = nil
                    }
                }
            )
        
        GeometryReader { geo in
            ZStack {
                LazyImage(request: ImageRequest(url: fullImageURL)) { state in
                    if state.error != nil {
                        Label("Failed to load image", systemImage: "exclamationmark.triangle.fill")
                            .centered()
                            .background(theme.lineColor.opacity(0.2))
                            .onAppear {
                                L.og.debug("Failed to load image: \(state.error?.localizedDescription ?? "")")
                            }
                    }
                    else if let container = state.imageContainer, container.type ==  .gif, let data = container.data {
                        GIFImage(data: data)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scaleEffect(scale)
                            .offset(position)
                            .gesture(magnifyAndDragGesture)
                            .onTapGesture {
                                withAnimation {
                                    scale = 1.0
                                }
                            }
                            .onAppear {
                                sharableGif = data
                            }
                    }
                    else if let image = state.image {
                        image
                            .resizable()
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(scale)
                            .offset(position)
                            .gesture(magnifyAndDragGesture)
                            .onTapGesture {
                                withAnimation {
                                    scale = 1.0
                                }
                            }
                            .onAppear {
                                if let image = state.imageContainer?.image {
                                    sharableImage = image
                                }
                            }
                    }
                    else if state.isLoading { // does this conflict with showing preview images??
                        HStack(spacing: 5) {
                            ImageProgressView(progress: state.progress)
                            Image(systemName: "multiply.circle.fill")
                                .padding(10)
                        }
                        .centered()
                        .background(theme.lineColor)
                    }
                    else {
                        theme.lineColor.opacity(0.2)
                    }
                }
                .pipeline(ImageProcessing.shared.content)
                .priority(.high)
                VStack {
                    HStack {
                        Spacer()
                        if let sharableImage {
                            ShareMediaButton(sharableImage: sharableImage)
                        }
                        else if let sharableGif {
                            ShareGifButton(sharableGif: sharableGif)
                        }
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .padding(30)
                            .onTapGesture {
                                dismiss()
                            }
                            .zIndex(10)
                    }
                    Spacer()
                }
                .onTapGesture {
                    dismiss()
                    //                fullImageIsShown = false
                }
            }
        }
    }
}

struct FullScreenItem : Identifiable {
    var url:URL
    var id:String { url.absoluteString }
}

struct ShareMediaButton: View {
    
    var sharableImage:UIImage
    @State private var showShareSheet = false

    
    var body: some View {
        Button { showShareSheet = true } label: { Image(systemName: "square.and.arrow.up") }
            .sheet(isPresented: $showShareSheet) {
                let item = NSItemProvider(item: sharableImage.pngData()! as NSData, typeIdentifier: "public.png")
                ActivityView(activityItems: [item])
            }
                        
    }
}

struct ShareGifButton: View {
    
    var sharableGif:Data
    @State private var showShareSheet = false

    
    var body: some View {
        Button { showShareSheet = true } label: { Image(systemName: "square.and.arrow.up") }
            .sheet(isPresented: $showShareSheet) {
                let item = NSItemProvider(item: sharableGif as NSData, typeIdentifier: "com.compuserve.gif")
                ActivityView(activityItems: [item])
            }
                        
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

func getImgUrlsFromContent(_ content:String) -> [URL] {
    var urls:[URL] =  []
    let range = NSRange(content.startIndex..<content.endIndex, in: content)
    let matches = mediaRegex.matches(in: content, range: range)
    for match in matches {
        let url = (content as NSString).substring(with: match.range)
        if let urlURL = URL(string: url) {
            urls.append(urlURL)
        }
    }
    return urls
}

let mediaRegex = try! NSRegularExpression(pattern: "(?i)https?:\\/\\/\\S+?\\.(?:mp4|mov|m4a|m3u8|png|jpe?g|gif|webp|bmp)(\\?\\S+){0,1}\\b")
