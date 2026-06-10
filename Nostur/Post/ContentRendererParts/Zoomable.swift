//
//  Zoomable.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/03/2025.
//

import SwiftUI
import NavigationBackport

struct ZoomableItem<Content: View, DetailContent: View>: View {
    @Environment(\.nxViewingContext) private var nxViewingContext
    private let id: String
    private let content: Content
    private let detailContent: DetailContent
    private var frameSize: CGSize? = nil

    init(id: String = "Default", @ViewBuilder _ content: () -> Content, frameSize: CGSize? = nil, @ViewBuilder detailContent: () -> DetailContent) {
        self.id = id
        self.content = content()
        self.detailContent = detailContent()
        self.frameSize = frameSize
    }

    var body: some View {
        content
            .modifier {
                if let frameSize {
                    $0.frame(width: frameSize.width, height: frameSize.height)
                }
                else {
                    $0
                }
            }
            .overlay(
                // Hero zoom: the fullscreen view should grow out of this thumbnail, so measure the
                // thumbnail's actual frame at tap time (in the paired Zoomable's coordinate space).
                // Must be an overlay: an Image is opaque to hit testing even without gestures, so a
                // tap layer behind it would never receive touches.
                GeometryReader { geo in
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !nxViewingContext.contains(.preview) else { return }
                            let frame = geo.frame(in: .named("zoomable-\(id)"))
                            triggerZoom(origin: CGPoint(x: frame.midX, y: frame.midY), startingSize: frame.size)
                        }
                }
            )
    }

    private func triggerZoom(origin: CGPoint, startingSize: CGSize) {
        let zoomRequest = ZoomRequested(id: self.id, origin: origin, startingSize: startingSize, content: detailContent)
        sendNotification(.zoomRequested, zoomRequest)
    }
}

struct Zoomable<Content: View>: View {
    public let id: String
    private let content: Content
    
    @State private var viewState: ZoomState = .off
    @State private var detailContent: AnyView?
    @State private var detailScale: CGFloat = 1.0
    @State private var originOffset = CGPoint(x: 0, y: 0)
    @State private var animationProgress: CGFloat = 0
    @State private var startingSize = CGSize(width: 100, height: 100)
    @State private var screenSize: CGSize = .zero
    @State private var fullScreenSize: CGSize = UIScreen.main.bounds.size
    
    init(id: String = "Default", @ViewBuilder _ content: () -> Content) {
        self.id = id
        self.content = content()
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                content
//                    .environmentObject(screenSpace)
                
                if viewState == .zoomed {
                    ZStack(alignment: .topLeading) {
                        // Content container: laid out at full size once, then transformed from the
                        // thumbnail's rect to fullscreen (scale/position/opacity are render-server
                        // animations, cheaper than animating layout)
                        if let detailContent {
                            detailContent
                                .environment(\.fullScreenSize, fullScreenSize)
                                .frame(width: screenSize.width, height: screenSize.height)
                                .scaleEffect(zoomScale)
                                .position(
                                    x: originOffset.x + ((screenSize.width / 2) - originOffset.x) * animationProgress,
                                    y: originOffset.y + ((screenSize.height / 2) - originOffset.y) * animationProgress
                                )
                                .opacity(min(1.0, animationProgress * 2)) // quick fade-in over the thumbnail
                        }
                        
                        CloseButton(action: closeWithAnimation)
                            .foregroundColor(.white)
                            .opacity(animationProgress)
                            .zIndex(2)
                    }
                }
            }
            .coordinateSpace(name: "zoomable-\(id)") // ZoomableItem measures thumbnail frames in this space
            .onAppear {
                screenSize = geometry.size
                if id == "Default" {
                    // Need to set because on Desktop full screen size should be just the window size
                    fullScreenSize = geometry.size
                    ScreenSpace.shared.screenSize = geometry.size
                }
            }
            .onChange(of: geometry.size) { newSize in
                screenSize = newSize
                if id == "Default" {
                    // Need to set because on Desktop full screen size should be just the window size
                    fullScreenSize = newSize
                    ScreenSpace.shared.screenSize = newSize
                }
            }
        }
//        .edgesIgnoringSafeArea(.all)
        .onReceive(receiveNotification(.zoomRequested)) { notification in
            if let zoomRequest = notification.object as? ZoomRequested {
                guard zoomRequest.id == self.id else { return }
                if let typedContent = zoomRequest.content as? AnyView {
                    self.startingSize = zoomRequest.startingSize
                    self.originOffset = CGPoint(
                        x: zoomRequest.origin.x,
                        y: zoomRequest.origin.y
                    )
                    
                    zoom(from: zoomRequest.origin, detailContent: typedContent)
                }
            }
        }
        .onReceive(receiveNotification(.closeFullscreenGallery)) { _ in
            closeWithAnimation()
        }
    }
    
    // Uniform scale that covers the thumbnail's rect at progress 0 and reaches fullscreen at 1
    private var zoomScale: CGFloat {
        let startScale = max(
            startingSize.width / max(1, screenSize.width),
            startingSize.height / max(1, screenSize.height)
        )
        return startScale + (1.0 - startScale) * animationProgress
    }

    private func zoom(from: CGPoint, detailContent: AnyView) {
        self.detailContent = detailContent
        self.viewState = .zoomed
        self.animationProgress = 0

        withAnimation(.spring(duration: 0.25)) {
            self.animationProgress = 1.0
        }
    }
    
    private func closeWithAnimation() {
        guard viewState != .off else { return }
        withAnimation(.easeIn(duration: 0.1)) {
            self.animationProgress = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            close()
        }
    }
    
    private func close() {
        viewState = .off
        animationProgress = 0
        originOffset = CGPoint(x: 0, y: 0)
    }
}

enum ZoomState {
    case off
    case zoomed
}

struct ZoomRequested {
    let id: String
    let origin: CGPoint
    let startingSize: CGSize
    let content: any View
    
    init<C: View>(id: String = "Default", origin: CGPoint, startingSize: CGSize, content: C) {
        self.id = id
        self.origin = origin
        self.startingSize = startingSize
        self.content = AnyView(content)
    }
}

#Preview {
    NBNavigationStack {
        Zoomable {
            VStack {
                Color.red
                    .overlay(alignment: .trailing) {
                        ZoomableItem {
                            Image("NosturLogo")
                                .resizable()
                                .scaledToFit()
                        } detailContent: {
                            Image("NosturLogo")
                                .resizable()
                                .scaledToFit()
                                .overlay {
                                    HStack {
                                        Button("Previous", systemImage: "chevron.left") {
                                            
                                        }
                                        Spacer()
                                        Button("Next", systemImage: "chevron.right") {
                                            
                                        }
                                    }
                                }
                        }
                    }
                Color.green
                Color.blue
                Color.pink
                    .overlay(alignment: .leading) {
                        ZoomableItem {
                            Image("HashtagNostr")
                                .resizable()
                                .scaledToFit()
                        } detailContent: {
                            Image("HashtagNostr")
                                .resizable()
                                .scaledToFit()
                        }
                    }
            }
        }
    }
}

// .matchedGeometryEffect(id: "image", in: namespace)
// .edgesIgnoringSafeArea(.all)
// .animation(.easeOut(duration: 0.5), value: showFullImage)

// Only for FULL WIDTH (main + detailpane)
// Normally use \.fullScreenSize environment key, but we need access in makeImageRequest() so store in this singleton
// Only update from Zoomable.id == "Default" (.sheet on on Desktop can have separate Zoomable with smaller size)
class ScreenSpace {
    public var screenSize: CGSize = UIScreen.main.bounds.size
    public var mainTabSize: CGSize = UIScreen.main.bounds.size
    public var columnWidth: CGFloat = 200.0 // Needed for setting audio only bar width. Set from MacMainWindow
    
    static let shared = ScreenSpace()
    private init() { }
    
}
