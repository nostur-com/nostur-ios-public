//
//  Zoomable.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/03/2025.
//

import SwiftUI
import NavigationBackport

struct ZoomableItem<Content: View, DetailContent: View>: View {
    private let id: String
    private let content: Content
    private let detailContent: DetailContent
    private var frameSize: CGSize? = nil
    @State private var contentSize: CGSize = CGSize(width: 50, height: 50)
    @State private var viewPosition: CGPoint = .zero
    
    init(id: String = "Default", @ViewBuilder _ content: () -> Content, frameSize: CGSize? = nil, @ViewBuilder detailContent: () -> DetailContent) {
        self.id = id
        self.content = content()
        self.detailContent = detailContent()
        self.frameSize = frameSize
    }
    
    var body: some View {
        if let frameSize, #available(iOS 16.0, *) {
            GeometryReader { geometry in
                content
                    .onTapGesture(coordinateSpace: .global) { _ in
                        let frame = geometry.frame(in: .global)
                        triggerZoom(origin: CGPoint(x: frame.minX + (contentSize.width/2), y: frame.minY + (contentSize.height/2)))
                    }
            }
            .frame(width: frameSize.width, height: frameSize.height)
        }
        else if #available(iOS 16.0, *) {
            GeometryReader { geometry in
                content
                    .readSize(onChange: { size in
                        guard contentSize != size else { return }
                        contentSize = size
                    })
                    .onTapGesture(coordinateSpace: .global) { _ in
                        let frame = geometry.frame(in: .global)
                        triggerZoom(origin: CGPoint(x: frame.minX + (contentSize.width/2), y: frame.minY + (contentSize.height/2)))
                    }
            }
        } else {
            // Fallback on earlier versions
            content
                .onTapGesture {
                    triggerZoom(origin: CGPoint(x: UIScreen.main.bounds.width/2, y: UIScreen.main.bounds.height/2))
                }
        }
    }
    
    private func triggerZoom(origin: CGPoint) {
        let zoomRequest = ZoomRequested(id: self.id, origin: origin, startingSize: contentSize, content: detailContent)
        sendNotification(.zoomRequested, zoomRequest)
    }
}

struct Zoomable<Content: View>: View {
    @StateObject private var screenSpace: ScreenSpace = .shared
    
    public let id: String
    private let content: Content
    
    @State private var viewState: ZoomState = .off
    @State private var detailContent: AnyView?
    @State private var detailScale: CGFloat = 1.0
    @State private var originOffset = CGPoint(x: 0, y: 0)
    @State private var animationProgress: CGFloat = 0
    @State private var startingSize = CGSize(width: 100, height: 100)
    @State private var screenSize: CGSize = .zero
    
    init(id: String = "Default", @ViewBuilder _ content: () -> Content) {
        self.id = id
        self.content = content()
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                content
                    .environmentObject(screenSpace)
                
                if viewState == .zoomed {
                    ZStack(alignment: .topLeading) {
                        // Content container
                        if let detailContent {
                            detailContent
                                .environmentObject(screenSpace)
                                .frame(
                                    width: startingSize.width + (screenSize.width - startingSize.width) * animationProgress,
                                    height: startingSize.height + (screenSize.height - startingSize.height) * animationProgress
                                )
                                .position(
                                    x: originOffset.x + ((screenSize.width / 2) - originOffset.x) * animationProgress,
                                    y: originOffset.y + ((screenSize.height / 2) - originOffset.y) * animationProgress
                                )
                        }
                        
                        // Close button
                        Button(action: {
                            closeWithAnimation()
                        }) {
                            Image(systemName: "multiply")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding()
                        }
                        .opacity(animationProgress)
                        .zIndex(2)
                    }
                }
            }
            .onAppear {
                screenSize = geometry.size
                screenSpace.screenSize = geometry.size
            }
            .onChange(of: geometry.size) { newSize in
                screenSize = newSize
                screenSpace.screenSize = newSize
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
    
    private func zoom(from: CGPoint, detailContent: AnyView) {
        self.detailContent = detailContent
        self.viewState = .zoomed
        self.animationProgress = 0
        
        withAnimation(.easeOut(duration: 0.1)) {
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

class ScreenSpace: ObservableObject {
    @Published var screenSize: CGSize = UIScreen.main.bounds.size
    
    static let shared = ScreenSpace()
    private init() { }
    
}
