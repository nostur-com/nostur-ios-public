//
//  Zoomable.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/03/2025.
//

import SwiftUI
import NavigationBackport

struct ZoomableItem<Content: View, DetailContent: View>: View {
    private let content: Content
    private let detailContent: DetailContent
    @State private var contentSize: CGSize = CGSize(width: 50, height: 50)
    @State private var viewPosition: CGPoint = .zero
    
    init(@ViewBuilder _ content: () -> Content, @ViewBuilder detailContent: () -> DetailContent) {
        self.content = content()
        self.detailContent = detailContent()
    }
    
    var body: some View {
        if #available(iOS 16.0, *) {
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
        }
    }
    
    private func triggerZoom(origin: CGPoint) {
        print("triggerzoom from position: \(viewPosition)")
        let zoomRequest = ZoomRequested(origin: origin, startingSize: contentSize, content: detailContent)
        sendNotification(.zoomRequested, zoomRequest)
    }
}

struct Zoomable<Content: View>: View {
    @StateObject private var screenSpace: ScreenSpace = .shared
    
    private let content: Content
    
    @State private var viewState: ZoomState = .off
    @State private var detailContent: AnyView?
    @State private var detailScale: CGFloat = 1.0
    @State private var originOffset = CGPoint(x: 0, y: 0)
    @State private var animationProgress: CGFloat = 0
    @State private var startingSize = CGSize(width: 100, height: 100)
    @State private var screenSize: CGSize = .zero
    
    init(@ViewBuilder _ content: () -> Content) {
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
    let origin: CGPoint
    let startingSize: CGSize
    let content: any View
    
    init<C: View>(origin: CGPoint, startingSize: CGSize, content: C) {
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
