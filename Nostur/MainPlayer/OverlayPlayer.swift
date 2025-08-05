//
//  OverlayPlayer.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/01/2025.
//

import SwiftUI
import NavigationBackport
@_spi(Advanced) import SwiftUIIntrospect

let AUDIOONLYPILL_HEIGHT: CGFloat = 48.0
let CONTROLS_HEIGHT: CGFloat = 60.0
let TOOLBAR_HEIGHT: CGFloat = 160.0 // TODO: Fix magic number 160 or make sure its correct. This fixes "close" button and toolbar missing because video height is too high

struct OverlayPlayer: View {
    
    @Environment(\.theme) private var theme
    @ObservedObject var vm: AnyPlayerModel = .shared
    
    private var videoHeight: CGFloat {
        if vm.viewMode == .detailstream {
            // 3rd of screen height or video height if smaller
            return min(ScreenSpace.shared.screenSize.height / 3, videoWidth / vm.aspect)
        }
        if vm.viewMode == .audioOnlyBar {
            return AUDIOONLYPILL_HEIGHT
        }
        
        return min(videoWidth / vm.aspect, ScreenSpace.shared.screenSize.height - TOOLBAR_HEIGHT)
    }
    
    private var videoWidth: CGFloat {
        if vm.viewMode == .audioOnlyBar {
            return ScreenSpace.shared.mainTabSize.width
        }
        if vm.viewMode != .overlay {
            return ScreenSpace.shared.screenSize.width
        }
        return ScreenSpace.shared.screenSize.width * 0.45
    }
    
    private var avPlayerHeight: CGFloat {
        if vm.viewMode == .overlay {
            return videoHeight
        }
        if vm.viewMode == .audioOnlyBar {
            return AUDIOONLYPILL_HEIGHT
        }
        if vm.viewMode == .detailstream {
            // 3rd of screen height or video height if smaller
            return min(ScreenSpace.shared.screenSize.height / 3, videoWidth / vm.aspect)
        }
        return videoHeight
    }
    
    private var frameHeight: CGFloat {
        
        // AUDIO ONLY PILL HEIGHT
        if vm.viewMode == .audioOnlyBar {
            return AUDIOONLYPILL_HEIGHT
        }
        
        // OVERLAY HEIGHT
        if vm.viewMode == .overlay {
            return (min(videoHeight, ScreenSpace.shared.screenSize.height - CONTROLS_HEIGHT) * currentScale) + CONTROLS_HEIGHT
        }
        
        // STREAMDETAIL HEIGHT
        if vm.viewMode == .detailstream {
            return ScreenSpace.shared.screenSize.height
        }
        
        // FULLSCREEN 
        return ScreenSpace.shared.screenSize.height - TOOLBAR_HEIGHT
    }
    
    // State variables for dragging
    @State private var currentOffset = CGSize(width: ScreenSpace.shared.screenSize.width * 0.45, height: ScreenSpace.shared.screenSize.height - 280.0) // Initial Y offset
    @State private var dragOffset = CGSize(width: ScreenSpace.shared.screenSize.width * 0.45, height: .zero)
    
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
    @State private var bookmarkState = false
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        GeometryReader { geometry in
            if vm.isShown {
                ZStack(alignment: videoAlignment) {
                    // -- MARK: .fullscreen toolbar (ONLY the toolbar)
                    // .detailstream has different toolbar
                    if vm.viewMode == .fullscreen {
                        NRNavigationStack {
                            Color.black
                                .toolbar {
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
                                    
                                    // BOOKMARK BUTTON
                                    ToolbarItem(placement: .topBarTrailing) {
                                        if vm.nrPost != nil, vm.availableViewModes.contains(.overlay) && vm.viewMode != .overlay {
                                            Button("Bookmark", systemImage: bookmarkState ? "bookmark.fill" : "bookmark") {
                                                bookmarkState.toggle()
                                            }
                                            .font(.title2)
                                            .buttonStyle(.borderless)
                                            .foregroundColor(Color.white)
                                        }
                                    }
                                    
                                    // SAVE BUTTON
                                    ToolbarItem(placement: .topBarTrailing) {
                                        if !vm.isStream && vm.viewMode != .overlay {
                                            Menu(content: {
                                                Button("Save to Photo Library") {
                                                    saveAVAssetToPhotos()
                                                }
                                                Button("Copy video URL") {
                                                    if let url = vm.currentlyPlayingUrl {
                                                        UIPasteboard.general.string = url
                                                        sendNotification(.anyStatus, ("Video URL copied to clipboard", "APP_NOTICE"))
                                                    }
                                                }
                                            }, label: {
                                                if isSaving {
                                                    HStack {
                                                        ProgressView()
                                                        Text(vm.downloadProgress, format: .percent)
                                                    }
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
                                            })
                                            .disabled(isSaving)
                                            .font(.title2)
                                            .foregroundColor(Color.white)
                                        }
                                    }
                                    
                                    // PIP BUTTON
                                    ToolbarItem(placement: .topBarTrailing) {
                                        if vm.availableViewModes.contains(.overlay) && vm.viewMode != .overlay {
                                            Button("Picture-in-Picture", systemImage: "pip.enter") {
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
                                .onDisappear {
                                    AnyPlayerModel.shared.downloadTask?.cancel()
                                    isSaving = false
                                    didSave = false
                                }
                                .background(Color.black) // Needed for toolbar bg
                        }
                    }
                        
                    VStack(spacing: 0) {
                        NRNavigationStack {
                            VStack(spacing: 0) {
                                // -- MARK: Actual video/stream ( .overlay + .full + .stream + .audioOnlyPill)
                                Color.black
                                    .overlay {
                                        if vm.isLoading {
                                            ProgressView()
                                        }
                                    }
                                    .overlay {
                                        if !vm.isLoading {
                                            AVPlayerViewControllerRepresentable(player: $vm.player, isPlaying: $vm.isPlaying, showsPlaybackControls: $vm.showsPlaybackControls, viewMode: $vm.viewMode)
                                        }
                                    }
                                    .frame(maxHeight: avPlayerHeight)
                                    .animation(.smooth, value: vm.viewMode)
                                    .overlay { // MARK: Overlay after finished playing
                                        if vm.didFinishPlaying {
                                            ZStack {
                                                Color.black.opacity(0.75)
                                                    .gesture(DragGesture(minimumDistance: 3.0, coordinateSpace: .local)
                                                        .onEnded({ value in
                                                            // close on swipe down
                                                            if value.translation.height > 0 {
                                                                vm.close()
                                                            }
                                                        }))
                                                    // Need high priority gesture, else cannot go from .overlay to .fullscreen
                                                    // but in .fullscreen we don't need high priority gesture because it interferes with playback controls
                                                    // so use custom .highPriorityGestureIf()
                                                    // put behind like button, else can't tap, see below again same code
                                                    .highPriorityGestureIf(condition: vm.viewMode == .overlay, gesture: TapGesture()
                                                        .onEnded {
                                                            withAnimation {
                                                                vm.toggleViewMode()
                                                            }
                                                        }
                                                    )
                                                
                                                VStack {
                                                    
                                                    if vm.viewMode != .overlay {
                                                        Image(systemName: "memories")
                                                            .resizable()
                                                            .scaledToFit()
                                                            .frame(width: 70, height: 70)
                                                            .foregroundColor(Color.white)
                                                            .contentShape(Rectangle())
                                                            .accessibilityHint("Replay")
                                                            .onTapGesture {
                                                                vm.replay()
                                                            }
                                                            .padding(.bottom, 30)
                                                    }
                                                    
                                                    if let nrPost = vm.nrPost {
                                                        HStack {
                                                            EmojiButton(nrPost: nrPost, isFirst: true, isLast: false)
                                                                .foregroundColor(theme.footerButtons)
                                                            if IS_NOT_APPSTORE { // Only available in non app store version
                                                                ZapButton(nrPost: nrPost, isFirst: false, isLast: false)
                                                                    .opacity(nrPost.contact.anyLud ? 1 : 0.3)
                                                                    .disabled(!nrPost.contact.anyLud)
                                                            }
                                                            else {
                                                                EmptyView()
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .overlay(alignment: .topLeading) {
                                        if vm.viewMode == .overlay {
                                            Image(systemName: "multiply")
                                                .font(.title2)
                                                .foregroundColor(Color.white)
                                                .opacity(0.8)
                                                .padding(5)
                                                .contentShape(Rectangle())
                                                .highPriorityGesture(
                                                    TapGesture()
                                                    .onEnded({ _ in
                                                        withAnimation {
                                                            vm.close()
                                                        }
                                                    }))
                                        }
                                    }
                                    .overlay(alignment: .bottomLeading) {
                                        if vm.viewMode == .overlay {
                                            Image(systemName: "rectangle.bottomthird.inset.filled")
                                                .frame(height: 28)
                                                .foregroundColor(Color.white)
                                                .opacity(0.8)
                                                .padding(5)
                                                .contentShape(Rectangle())
                                                .highPriorityGesture(
                                                    TapGesture()
                                                    .onEnded({ _ in
                                                        withAnimation {
                                                            vm.viewMode = .audioOnlyBar
                                                        }
                                                    }))
                                        }
                                    }
                                    // Need high priority gesture, else cannot go from .overlay to .fullscreen
                                    // but in .fullscreen we don't need high priority gesture because it interferes with playback controls
                                    // so use custom .highPriorityGestureIf()
                                    // but with this cannot tap like button, so only do when  !vm.didFinishPlaying
                                    .onTapGesture {
                                        withAnimation {
                                            vm.toggleViewMode()
                                        }
                                    }
//                                    .highPriorityGestureIf(condition: vm.viewMode == .overlay && !vm.didFinishPlaying, gesture: TapGesture()
//                                            .onEnded {
//                                                withAnimation {
//                                                    vm.toggleViewMode()
//                                                }
//                                        }
//                                    )
                                    .onDisappear {
                                        // Restore normal idle behavior
                                        UIApplication.shared.isIdleTimerDisabled = false
                                    }
                                
                                if vm.viewMode == .detailstream {
                                    if let nrLiveEvent = vm.nrLiveEvent {
                                        AvailableWidthContainer {
                                            StreamDetail(liveEvent: nrLiveEvent)
                                        }
                                    }
                                    else {
                                        EmptyView()
                                    }
                                }
                            }
                            .toolbar { // MARK: Toolbar for detailstream
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
                                        .foregroundColor(theme.accent)
                                    }
                                }
                                
                                // SAVE BUTTON
                                ToolbarItem(placement: .topBarTrailing) {
                                    if !vm.isStream && vm.viewMode == .detailstream {
                                        Menu(content: {
                                            Button("Save to Photo Library") {
                                                saveAVAssetToPhotos()
                                            }
                                            .tint(Color.white)
                                            .foregroundColor(theme.accent)
                                            
                                            Button("Copy video URL") {
                                                if let url = vm.currentlyPlayingUrl {
                                                    UIPasteboard.general.string = url
                                                    sendNotification(.anyStatus, ("Video URL copied to clipboard", "APP_NOTICE"))
                                                }
                                            }
                                            .foregroundColor(theme.accent)
                                            
                                        }, label: {
                                            if isSaving {
                                                HStack {
                                                    ProgressView()
                                                    Text(vm.downloadProgress, format: .percent)
                                                }
                                                .foregroundColor(Color.white)
                                                .tint(theme.accent)
                                                .padding(5)
                                            }
                                            else if didSave {
                                                Image(systemName: "square.and.arrow.down.badge.checkmark.fill")
                                                    .tint(theme.accent)
                                                    .foregroundColor(theme.accent)
                                                    .padding(5)
                                                    .offset(y: -2)
                                            }
                                            else {
                                                Image(systemName: "square.and.arrow.down")
                                                    .tint(theme.accent)
                                                    .foregroundColor(theme.accent)
                                                    .padding(5)
                                                    .offset(y: -6)
                                            }
                                        })
                                        .disabled(isSaving)
                                        .font(.title2)
                                        .foregroundColor(theme.accent)
                                    }
                                }
                                
                                // PIP BUTTON
                                ToolbarItem(placement: .topBarTrailing) {
                                    if vm.availableViewModes.contains(.overlay) && vm.viewMode == .detailstream {
                                        Button("Picture-in-picture", systemImage: "pip.enter") {
                                            withAnimation {
                                                vm.toggleViewMode()
                                            }
                                        }
                                        .font(.title2)
                                        .buttonStyle(.borderless)
                                        .foregroundColor(theme.accent)
                                    }
                                }
                            }
                        }
                        .introspect(.navigationStack, on: .iOS(.v16...)) {
                            $0.viewControllers.forEach { controller in
                                controller.view.backgroundColor = .clear
                            }
                        }
                        
                        // MARK: Video controls for .overlay mode
                        if vm.viewMode == .overlay {
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
                        // MARK: Video controls for .audioOnlyPill mode
                        else if vm.viewMode == .audioOnlyBar {
                            AudioOnlyBar()                                
                        }
                        else {
                            Spacer()
                        }
                    }
                    .ultraThinMaterialIfDetail(vm.viewMode)
                    .frame(
                        width: videoWidth * currentScale,
                        height: frameHeight
                    )
                    .offset(
                        x: clampedOffsetX(geometry: geometry),
                        y: clampedOffsetY(geometry: geometry) - (vm.viewMode == .overlay ? CONTROLS_HEIGHT : 0)
                    )
                    .gestureIf(condition: vm.viewMode == .fullscreen, gesture: DragGesture(minimumDistance: 3.0, coordinateSpace: .local)
                        .onEnded({ value in
                            // close on swipe down
                            if value.translation.height > 0 {
                                vm.close()
                            }
                        }))
                    .highPriorityGestureIf(condition: vm.viewMode == .overlay, gesture:
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
                    if vm.viewMode != .overlay && scale != 1.0 {
                        scale = 1.0
                    }
                }
                
                
                .onAppear {
                    guard let nrPost = vm.nrPost else {
                        bookmarkState = false
                        return
                    }
                    if let accountCache = accountCache(), accountCache.getBookmarkColor(nrPost.id) != nil {
                        bookmarkState = true
                    }
                    else if Bookmark.hasBookmark(eventId: nrPost.id, context: viewContext()) {
                        bookmarkState = true
                    }
                    else {
                        bookmarkState = false
                    }
                }
                .onChange(of: bookmarkState) { [bookmarkState] newState in
                    guard let nrPost = vm.nrPost else { return }
                    guard bookmarkState != newState else { return } // don't add or remove if already done
                    
                    let didHaveBookMark = Bookmark.hasBookmark(eventId: nrPost.id, context: viewContext())
                    
                    if newState && !didHaveBookMark {
                        Bookmark.addBookmark(nrPost)
                    }
                    else if !newState && didHaveBookMark {
                        Bookmark.removeBookmark(nrPost)
                    }
                }
                .onChange(of: vm.nrPost) { newNRPost in
                    guard let newNRPost else {
                        bookmarkState = false
                        return
                    }
                    if let accountCache = accountCache(), accountCache.getBookmarkColor(newNRPost.id) != nil {
                        bookmarkState = true
                    }
                    else if Bookmark.hasBookmark(eventId: newNRPost.id, context: viewContext()) {
                        bookmarkState = true
                    }
                    else {
                        bookmarkState = false
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
        if vm.viewMode == .audioOnlyBar { return 0 }
        
        let totalWidth = videoWidth * currentScale + 2
        let maxOffsetX = geometry.size.width - totalWidth
        return clamp(value: currentOffset.width + dragOffset.width, min: 0, max: maxOffsetX)
    }
    
    /// Calculates the clamped Y offset to ensure the video stays within vertical bounds.
    private func clampedOffsetY(geometry: GeometryProxy) -> CGFloat {
        if vm.viewMode == .detailstream { return 0 }
        if vm.viewMode == .fullscreen { return 0 }
        if vm.viewMode == .audioOnlyBar { return ScreenSpace.shared.screenSize.height - 98.0}
        
        let maxOffsetY = geometry.size.height - (videoHeight * currentScale)
        return clamp(value: currentOffset.height + dragOffset.height, min: 0, max: maxOffsetY)
    }
    
    func saveAVAssetToPhotos() {
        guard !didSave else { return }
        isSaving = true
        vm.downloadProgress = 0
        
        Task {
            if let avAsset = await vm.downloadVideo() {
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
            else {
                sendNotification(.anyStatus, ("Failed to get video", "APP_NOTICE"))
                isSaving = false
                return
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
