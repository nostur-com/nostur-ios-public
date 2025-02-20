//
//  OverlayVideo.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/01/2025.
//

import SwiftUI
import NavigationBackport
@_spi(Advanced) import SwiftUIIntrospect

let CONTROLS_HEIGHT: CGFloat = 60.0
let TOOLBAR_HEIGHT: CGFloat = 116.0

struct OverlayVideo<Content: View>: View {
    let content: Content
    
    @EnvironmentObject private var themes: Themes
    @ObservedObject var vm: AnyPlayerModel = .shared
    
    private var videoHeight: CGFloat {
        if vm.viewMode == .detailstream {
            return UIScreen.main.bounds.height / 3
        }
        return videoWidth / vm.aspect
    }
    
    private var videoWidth: CGFloat {
        if vm.viewMode != .overlay {
            return UIScreen.main.bounds.width
        }
        return UIScreen.main.bounds.width * 0.45
    }
    
    private var avPlayerHeight: CGFloat {
        if vm.viewMode == .overlay {
            return videoHeight
        }
        if vm.viewMode == .detailstream {
            return UIScreen.main.bounds.height / 3
        }
        return videoHeight
    }
    
    private var frameHeight: CGFloat {
        
        // OVERLAY HEIGHT
        if vm.viewMode == .overlay {
            return (min(videoHeight, UIScreen.main.bounds.height - CONTROLS_HEIGHT) * currentScale) + CONTROLS_HEIGHT
        }
        
        // STREAMDETAIL HEIGHT
        if vm.viewMode == .detailstream {
            return UIScreen.main.bounds.height
        }
        
        // FULLSCREEN 
        return UIScreen.main.bounds.height - TOOLBAR_HEIGHT
    }
    
    // State variables for dragging
    @State private var currentOffset = CGSize(width: UIScreen.main.bounds.width * 0.45, height: UIScreen.main.bounds.height - 280.0) // Initial Y offset
    @State private var dragOffset = CGSize(width: UIScreen.main.bounds.width * 0.45, height: .zero)
    
    // State variables for scaling
    @State private var currentScale: CGFloat = 1.0
    @State private var scale: CGFloat = 1.0
    @State private var nativeControlsVisible: Bool = false
    
    private var videoAlignment: Alignment {
        if vm.viewMode == .fullscreen { return .center }
        return .topLeading
    }
        
    // State variables for saving video
    @State private var isSaving = false
    @State private var didSave = false
    
    init(@ViewBuilder _ content: ()->Content) {
        self.content = content()
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        GeometryReader { geometry in
            if vm.isShown {
                ZStack(alignment: videoAlignment) {
                    if vm.viewMode == .fullscreen {
                        NBNavigationStack {
                            Color.black
                                .toolbar {
                                    // SAVE BUTTON
                                    ToolbarItem(placement: .topBarTrailing) {
                                        if !vm.isStream && vm.viewMode != .overlay {
                                            Menu(content: {
                                                Button("Save to Photo Library") {
                                                    saveAVAssetToPhotos()
                                                }
                                                Button("Copy video URL") {
                                                    if let url = vm.cachedVideo?.url {
                                                        UIPasteboard.general.string = url
                                                        sendNotification(.anyStatus, ("Video URL copied to clipboard", "APP_NOTICE"))
                                                    }
                                                }
                                            }, label: {
                                                if isSaving {
                                                    ProgressView()
                                                        .foregroundColor(Color.white)
                                                        .tint(Color.white)
                                                        .padding(5)
                                                }
                                                else if didSave {
                                                    Image(systemName: "square.and.arrow.down.badge.checkmark.fill")
                                                        .foregroundColor(Color.white)
                                                        .padding(5)
                                                        .offset(y: -2)
                                                }
                                                else {
                                                    Image(systemName: "square.and.arrow.down")
                                                        .foregroundColor(Color.white)
                                                        .padding(5)
                                                        .offset(y: -6)
                                                }
                                            }, primaryAction: saveAVAssetToPhotos)
                                            .disabled(isSaving)
                                            .font(.title2)
                                            .foregroundColor(Color.white)
                                        }
                                    }
                                    
                                    // CLOSE BUTTON
                                    ToolbarItem(placement: .topBarLeading) {
                                        if vm.viewMode != .overlay {
                                            Button("Close", systemImage: "multiply") {
                                                withAnimation {
                                                    vm.close()
                                                }
                                            }
                                            .font(.title2)
                                            .buttonStyle(.borderless)
                                            .foregroundColor(Color.white)
                                        }
                                    }
                                    
                                    // PIP BUTTON
                                    ToolbarItem(placement: .topBarTrailing) {
                                        if vm.availableViewModes.contains(.overlay) && vm.viewMode != .overlay {
                                            Button("Share", systemImage: "pip.enter") {
                                                withAnimation {
                                                    vm.toggleViewMode()
                                                }
                                            }
                                            .font(.title2)
                                            .buttonStyle(.borderless)
                                            .foregroundColor(Color.white)
                                        }
                                    }
                                }
                                .environmentObject(NRState.shared)
                                .environmentObject(themes)
                                .environmentObject(NewPostNotifier.shared)
                                .onDisappear {
                                    isSaving = false
                                    didSave = false
                                }
                                .background(Color.black) // Needed for toolbar bg
                        }
                    }
                        
                    VStack(spacing: 0) {
                        NBNavigationStack {
                            VStack(spacing: 0) {
                                AVPlayerViewControllerRepresentable(player: $vm.player, isPlaying: $vm.isPlaying, showsPlaybackControls: $vm.showsPlaybackControls, viewMode: $vm.viewMode)
                                    .frame(maxHeight: avPlayerHeight)
                                    .animation(.smooth, value: vm.viewMode)
                                    .overlay {
                                        if let nrPost = vm.nrPost, vm.didFinishPlaying {
                                            ZStack {
                                                Color.black.opacity(0.65)
                                                HStack {
                                                    LikeButton(nrPost: nrPost, isFirst: false, isLast: false, theme: themes.theme)
                                                        .foregroundColor(themes.theme.footerButtons)
                                                    if IS_NOT_APPSTORE { // Only available in non app store version
                                                        ZapButton(nrPost: nrPost, isFirst: false, isLast: false, theme: themes.theme)
                                                            .opacity(nrPost.contact?.anyLud ?? false ? 1 : 0.3)
                                                            .disabled(!(nrPost.contact?.anyLud ?? false))
                                                    }
                                                    else {
                                                        EmptyView()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    // Need high priority gesture, else cannot go from .overlay to .fullscreen
                                    // but in .fullscreen we don't need high priority gesture because it interferes with playback controls
                                    // so use custom .highPriorityGestureIf()
                                    .highPriorityGestureIf(condition: vm.viewMode == .overlay, onTap: {
                                        withAnimation {
                                            vm.toggleViewMode()
                                        }
                                    })
                                    .overlay(alignment: .topLeading) { // Close button for .overlay mode
                                        Image(systemName: "multiply")
                                            .font(.title2)
                                            .foregroundColor(Color.white)
                                            .padding(.top, 10)
                                            .padding(.leading, 10)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                withAnimation {
                                                    vm.close()
                                                }
                                            }
                                            .opacity(vm.viewMode == .overlay ? 1.0 : 0)
                                    }
                                
                                if vm.viewMode == .detailstream {
                                    content
                                }
                            }
                            .toolbar {
                                // SAVE BUTTON
                                ToolbarItem(placement: .topBarTrailing) {
                                    if !vm.isStream && vm.viewMode == .detailstream {
                                        Menu(content: {
                                            Button("Save to Photo Library") {
                                                saveAVAssetToPhotos()
                                            }
                                            .tint(Color.white)
                                            .foregroundColor(Color.white)
                                            
                                            Button("Copy video URL") {
                                                if let url = vm.cachedVideo?.url {
                                                    UIPasteboard.general.string = url
                                                    sendNotification(.anyStatus, ("Video URL copied to clipboard", "APP_NOTICE"))
                                                }
                                            }
                                            .foregroundColor(Color.white)
                                            
                                        }, label: {
                                            if isSaving {
                                                ProgressView()
                                                    .foregroundColor(Color.white)
                                                    .tint(Color.white)
                                                    .padding(5)
                                            }
                                            else if didSave {
                                                Image(systemName: "square.and.arrow.down.badge.checkmark.fill")
                                                    .tint(Color.white)
                                                    .foregroundColor(Color.white)
                                                    .padding(5)
                                                    .offset(y: -2)
                                            }
                                            else {
                                                Image(systemName: "square.and.arrow.down")
                                                    .tint(Color.white)
                                                    .foregroundColor(Color.white)
                                                    .padding(5)
                                                    .offset(y: -6)
                                            }
                                        }, primaryAction: saveAVAssetToPhotos)
                                        .disabled(isSaving)
                                        .font(.title2)
                                        .foregroundColor(Color.white)
                                    }
                                }
                                
                                // CLOSE BUTTON
                                ToolbarItem(placement: .topBarLeading) {
                                    if vm.viewMode == .detailstream {
                                        Button("Close", systemImage: "multiply") {
                                            withAnimation {
                                                vm.close()
                                            }
                                        }
                                        .font(.title2)
                                        .buttonStyle(.borderless)
                                        .foregroundColor(Color.white)
                                    }
                                }
                                
                                // PIP BUTTON
                                ToolbarItem(placement: .topBarTrailing) {
                                    if vm.availableViewModes.contains(.overlay) && vm.viewMode == .detailstream {
                                        Button("Share", systemImage: "pip.enter") {
                                            withAnimation {
                                                vm.toggleViewMode()
                                            }
                                        }
                                        .font(.title2)
                                        .buttonStyle(.borderless)
                                        .foregroundColor(Color.white)
                                    }
                                }
                            }
                            .environmentObject(NRState.shared)
                            .environmentObject(themes)
                            .environmentObject(NewPostNotifier.shared)
                        }
                        .introspect(.navigationStack, on: .iOS(.v16...)) {
                            $0.viewControllers.forEach { controller in
                                controller.view.backgroundColor = .clear
                            }
                        }
                        
                        if vm.viewMode == .overlay { // Video controls for .overlay mode
                            HStack(spacing: 30) {
                                Button(action: vm.seekBackward) {
                                    Image(systemName: "gobackward.15")
                                        .foregroundColor(Color.white)
                                        .font(.title)
                                }
                                
                                if vm.didFinishPlaying {
                                    Button("Replay", systemImage: "memories") {
                                        vm.replay()
                                    }
//                                    .tint(Color.white)
//                                    .accentColor(Color.white)
                                    .foregroundColor(Color.white)
                                    .font(.title)
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.plain)
                                }
                                else {
                                    Button(action: {
                                        if vm.isPlaying {
                                            vm.pauseVideo()
                                        }
                                        else {
                                            vm.playVideo()
                                        }
                                    }) {
                                        Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                                            .foregroundColor(Color.white)
                                            .font(.title)
                                    }
                                }
                                
                                Button(action: vm.seekForward) {
                                    Image(systemName: "goforward.15")
//                                            .foregroundColor(.white)
                                        .font(.title)
                                        .foregroundColor(Color.white)
                                }
                                    .opacity(vm.didFinishPlaying ? 0.0 : 1.0)
                            }
                            .frame(height: CONTROLS_HEIGHT)
                        }
                        else {
                            Spacer()
                        }
                    }
                    .ultraThinMaterialIfDetail(vm.viewMode)
//                    .frame(maxHeight: UIScreen.main.bounds.height - 75) // TODO: Fix magic number 75 or make sure its correct
                    .frame(
                        width: videoWidth * currentScale,
                        height: frameHeight
                    )
                    .offset(
                        x: clampedOffsetX(geometry: geometry),
                        y: clampedOffsetY(geometry: geometry) - (vm.viewMode == .overlay ? CONTROLS_HEIGHT : 0)
                    )
                    .highPriorityGesture(
                        DragGesture()
                            .onChanged { value in
                                guard vm.viewMode == .overlay else { return }
                                self.dragOffset = value.translation
                            }
                            .onEnded { value in
                                guard vm.viewMode == .overlay else { return }
                                let newOffsetX = currentOffset.width + value.translation.width
                                let newOffsetY = currentOffset.height + value.translation.height
                                
                                // Update currentOffset with clamped values
                                currentOffset.width = clamp(
                                    value: newOffsetX,
                                    min: 0,
                                    max: geometry.size.width - (videoWidth * currentScale + 2)
                                )
                                currentOffset.height = clamp(
                                    value: newOffsetY,
                                    min: 0,
                                    max: geometry.size.height - (videoHeight * currentScale)
                                )
                                dragOffset = .zero
                            }
                        
                        
                        // Combine Drag and Magnification Gestures
//                        SimultaneousGesture(
//                            DragGesture()
//                                .onChanged { value in
//                                    guard vm.viewMode == .overlay else { return }
//                                    self.dragOffset = value.translation
//                                }
//                                .onEnded { value in
//                                    guard vm.viewMode == .overlay else { return }
//                                    let newOffsetX = currentOffset.width + value.translation.width
//                                    let newOffsetY = currentOffset.height + value.translation.height
//                                    
//                                    // Update currentOffset with clamped values
//                                    currentOffset.width = clamp(
//                                        value: newOffsetX,
//                                        min: 0,
//                                        max: geometry.size.width - (videoWidth * currentScale + 2)
//                                    )
//                                    currentOffset.height = clamp(
//                                        value: newOffsetY,
//                                        min: 0,
//                                        max: geometry.size.height - (videoHeight * currentScale)
//                                    )
//                                    dragOffset = .zero
//                                },
//                            MagnificationGesture()
//                                .onChanged { value in
//                                    guard vm.viewMode == .overlay else { return }
//                                    let delta = value / self.scale
//                                    self.scale = value
//                                    var newScale = self.currentScale * delta
//                                    
//                                    // Calculate maximum and minimum scales based on geometry
//                                    let maxScaleWidth = geometry.size.width / videoWidth
//                                    let maxScaleHeight = geometry.size.height / videoHeight
//                                    let maxScale = min(maxScaleWidth, maxScaleHeight, 3.0) // 3.0 is an arbitrary upper limit
//                                    let minScale: CGFloat = 0.5 // 50% of original size
//                                    
//                                    // Clamp the new scale
//                                    newScale = clamp(value: newScale, min: minScale, max: maxScale)
//                                    
//                                    self.currentScale = newScale
//                                    
//                                    // Adjust currentOffset to ensure the video stays within bounds after scaling
//                                    currentOffset.width = clamp(
//                                        value: currentOffset.width,
//                                        min: 0,
//                                        max: geometry.size.width - (videoWidth * currentScale + 2)
//                                    )
//                                    currentOffset.height = clamp(
//                                        value: currentOffset.height,
//                                        min: 0,
//                                        max: geometry.size.height - (videoHeight * currentScale)
//                                    )
//                                }
////                                .onEnded { _ in
////                                    guard vm.viewMode == .overlay else { return }
////                                    self.scale = 1.0
////                                }
                    )
                }
                .onChange(of: vm.viewMode) { _ in
//                    print("UIScreen.main.bounds: \(UIScreen.main.bounds.width)x\(UIScreen.main.bounds.height)")
                    if vm.viewMode != .overlay && scale != 1.0 {
                        scale = 1.0
                    }
                }
            }
        }
    }
    
    /// Clamps a value between a minimum and maximum.
    private func clamp(value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        return Swift.max(min, Swift.min(max, value))
    }
    
    /// Calculates the clamped X offset to ensure the video stays within horizontal bounds.
    private func clampedOffsetX(geometry: GeometryProxy) -> CGFloat {
        if vm.viewMode == .detailstream { return 0 }
        if vm.viewMode == .fullscreen { return 0 }
        
        let totalWidth = videoWidth * currentScale + 2
        let maxOffsetX = geometry.size.width - totalWidth
        return clamp(value: currentOffset.width + dragOffset.width, min: 0, max: maxOffsetX)
    }
    
    /// Calculates the clamped Y offset to ensure the video stays within vertical bounds.
    private func clampedOffsetY(geometry: GeometryProxy) -> CGFloat {
        if vm.viewMode == .detailstream { return 0 }
        if vm.viewMode == .fullscreen { return 0 }
        
        let maxOffsetY = geometry.size.height - (videoHeight * currentScale)
        return clamp(value: currentOffset.height + dragOffset.height, min: 0, max: maxOffsetY)
    }
    
    func saveAVAssetToPhotos() {
        guard !didSave else { return }
        isSaving = true

        guard let avAsset = vm.cachedVideo?.asset else {
            sendNotification(.anyStatus, ("Failed to get video", "APP_NOTICE"))
            isSaving = false
            return
        }

        exportAsset(avAsset) { exportedURL in
            guard let url = exportedURL else {
                sendNotification(.anyStatus, ("Failed to export video", "APP_NOTICE"))
                isSaving = false
                return
            }

            requestPhotoLibraryAccess { granted in
                if granted {
                    saveVideoToPhotoLibrary(videoURL: url) { success, error in
                        if success {
                            didSave = true
                            sendNotification(.anyStatus, ("Saved to Photo Library", "APP_NOTICE"))
                        } else {
                            sendNotification(.anyStatus, ("Failed to save video: \(error?.localizedDescription ?? "Unknown error")", "APP_NOTICE"))
                        }
                        isSaving = false
                    }
                } else {
                    sendNotification(.anyStatus, ("Photo Library access was denied.", "APP_NOTICE"))
                    isSaving = false
                }
            }
        }
    }
}


import AVKit
import Photos

func exportAsset(_ asset: AVAsset, completion: @escaping (URL?) -> Void) {
    guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
        completion(nil)
        return
    }

    let exportDirectory = FileManager.default.temporaryDirectory
    let exportURL = exportDirectory.appendingPathComponent("exportedVideo.mp4")

    try? FileManager.default.removeItem(at: exportURL)

    exportSession.outputURL = exportURL
    exportSession.outputFileType = .mp4

    exportSession.exportAsynchronously {
        switch exportSession.status {
        case .completed:
            completion(exportURL)
        case .failed:
            print("Export failed: \(String(describing: exportSession.error))")
            completion(nil)
        case .cancelled:
            print("Export cancelled")
            completion(nil)
        default:
            print("Export other status: \(exportSession.status)")
            completion(nil)
        }
    }
}

func requestPhotoLibraryAccess(completion: @escaping (Bool) -> Void) {
    let status = PHPhotoLibrary.authorizationStatus()

    switch status {
    case .authorized, .limited:
        completion(true)
    case .notDetermined:
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
            DispatchQueue.main.async {
                completion(newStatus == .authorized || newStatus == .limited)
            }
        }
    default:
        completion(false)
    }
}

func saveVideoToPhotoLibrary(videoURL: URL, completion: @escaping (Bool, Error?) -> Void) {
    PHPhotoLibrary.shared().performChanges({
        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
    }) { success, error in
        DispatchQueue.main.async {
            // Optionally delete the temporary file
            try? FileManager.default.removeItem(at: videoURL)
            completion(success, error)
        }
    }
}

extension View {
    
    @ViewBuilder
    func ultraThinMaterialIfDetail(_ viewMode: AnyPlayerViewMode) -> some View {
        if viewMode == .detailstream {
            self.background(.ultraThinMaterial)
        }
        else {
            self.background(Color.black)
        }
    }
}
