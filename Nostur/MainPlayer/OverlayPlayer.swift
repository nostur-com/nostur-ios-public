//
//  OverlayPlayer.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/01/2025.
//

import SwiftUI
import NavigationBackport
@_spi(Advanced) import SwiftUIIntrospect
import AVKit
import Photos

let AUDIOONLYPILL_HEIGHT: CGFloat = 48.0
let CONTROLS_HEIGHT: CGFloat = 60.0
let FULLSCREEN_CONTROLS_HEIGHT: CGFloat = 86.0
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
            if IS_DESKTOP_COLUMNS() {
                return ScreenSpace.shared.columnWidth
            }
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
    
    // State variables for custom playback controls
    @State private var isMuted = false
    // Start hidden so opening a playing video isn't covered by chrome.
    @State private var fullscreenControlsVisible = false
    @State private var fullscreenControlsHideTask: Task<Void, Never>?
    @State private var detailStreamControlsVisible = false
    @State private var detailStreamControlsHideTask: Task<Void, Never>?
    @State private var shouldRestoreDetailStreamAfterRotatedFullscreen = false
    @State private var isRotatedFullscreen = false
    /// Tracks real macOS window full screen (green button / `NSWindow.toggleFullScreen`).
    @State private var isNativeMacFullScreen = false
    /// True when this player session requested native Mac full screen (so we can restore on close).
    @State private var enteredNativeMacFullScreenFromPlayer = false
    
    private var videoAlignment: Alignment {
        if vm.viewMode == .fullscreen { return .center }
        return .topLeading
    }
        
    // State variables for saving video
    @State private var isSaving = false
    @State private var didSave = false
    @State private var bookmarkState = false
    
    private var hasSeekableDuration: Bool {
        let durationSeconds = vm.player.currentItem?.duration.seconds ?? 0
        return durationSeconds.isFinite && durationSeconds > 0
    }
    
    private var shouldShowDetailStreamVideoControls: Bool {
        guard vm.viewMode == .detailstream,
              detailStreamControlsVisible,
              !shouldShowPlaybackSpinner else { return false }
        return vm.player.status != .failed && vm.player.currentItem?.status != .failed
    }

    private var shouldShowPlaybackSpinner: Bool {
        if vm.isLoading { return true }
        guard vm.isPlaying, !vm.didFinishPlaying else { return false }
        guard vm.player.status != .failed, vm.player.currentItem?.status != .failed else { return false }
        return vm.timeControlStatus != .playing
    }
    
    private var overlayControls: some View {
        HStack(spacing: 30) {
            controlButton(systemName: "gobackward.10", label: "Back 10 Seconds") {
                vm.seekBackward()
            }
            
            if vm.didFinishPlaying {
                controlButton(systemName: "memories", label: "Replay") {
                    vm.replay()
                }
            }
            else {
                controlButton(systemName: vm.isPlaying ? "pause.fill" : "play.fill", label: vm.isPlaying ? "Pause" : "Play") {
                    togglePlayPause()
                }
            }
            
            controlButton(systemName: "goforward.10", label: "Forward 10 Seconds") {
                vm.seekForward()
            }
            .opacity(vm.didFinishPlaying ? 0.0 : 1.0)
        }
        .frame(height: CONTROLS_HEIGHT)
        .background(Color.black)
    }
    
    @ViewBuilder
    private func fullscreenControls(isLandscape: Bool) -> some View {
        // Layout follows window aspect; on macOS the expand control toggles native
        // window full screen instead of iOS landscape rotation (see handleFullscreenExpandToggle).
        if isLandscape {
            landscapeFullscreenBottomControls()
        }
        else {
            portraitFullscreenControls()
        }
    }
    
    /// macOS: enter/exit based on real window full screen. iOS portrait: always "expand".
    private var portraitFullscreenExpandSystemName: String {
        if IS_CATALYST {
            return isNativeMacFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        }
        return "arrow.up.left.and.arrow.down.right"
    }
    
    private var portraitFullscreenExpandLabel: String {
        if IS_CATALYST {
            return isNativeMacFullScreen ? "Exit Full Screen" : "Enter Full Screen"
        }
        return "Rotate Full Screen"
    }
    
    /// macOS: enter/exit based on real window full screen. iOS landscape: always "exit".
    private var landscapeFullscreenExpandSystemName: String {
        if IS_CATALYST {
            return isNativeMacFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        }
        return "arrow.down.right.and.arrow.up.left"
    }
    
    private var landscapeFullscreenExpandLabel: String {
        if IS_CATALYST {
            return isNativeMacFullScreen ? "Exit Full Screen" : "Enter Full Screen"
        }
        return "Exit Full Screen"
    }
    
    /// macOS only: toggle real `NSWindow` full screen (not iOS orientation rotation).
    private func handleMacNativeFullscreenToggle() {
        guard IS_CATALYST else { return }
        let wasNativeFullScreen = isNativeMacFullScreen || isMacWindowInFullScreen()
        toggleNativeMacFullScreenFromPlayer()
        // Mirror iOS rotate-to-portrait: leaving expanded full screen returns to stream detail.
        if wasNativeFullScreen, shouldRestoreDetailStreamAfterRotatedFullscreen {
            shouldRestoreDetailStreamAfterRotatedFullscreen = false
            vm.viewMode = .detailstream
        }
    }
    
    private func portraitFullscreenControls() -> some View {
        VStack(spacing: 8) {
            fullscreenTimeline()
            
            HStack(spacing: 14) {
                fullscreenTransportControls(buttonSize: 36, iconFont: .system(size: 21, weight: .semibold), spacing: 18)
                
                Spacer(minLength: 12)
                
                fullscreenOutputControls()
                controlButton(systemName: portraitFullscreenExpandSystemName, label: portraitFullscreenExpandLabel) {
                    if IS_CATALYST {
                        handleMacNativeFullscreenToggle()
                    }
                    else {
                        rotateToLandscape()
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(height: FULLSCREEN_CONTROLS_HEIGHT)
        .background(fullscreenBottomGradient)
    }
    
    private func landscapeFullscreenBottomControls() -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Spacer()
                fullscreenOutputControls()
                controlButton(systemName: landscapeFullscreenExpandSystemName, label: landscapeFullscreenExpandLabel) {
                    if IS_CATALYST {
                        handleMacNativeFullscreenToggle()
                    }
                    else {
                        rotateToPortrait()
                    }
                }
            }
            
            fullscreenTimeline()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(fullscreenBottomGradient)
    }
    
    private func fullscreenOutputControls(buttonSize: CGFloat = 32, airPlaySize: CGFloat = 32, spacing: CGFloat = 16, iconFont: Font = .title3) -> some View {
        HStack(spacing: spacing) {
            controlButton(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: isMuted ? "Unmute" : "Mute", size: buttonSize, iconFont: iconFont) {
                toggleMute()
            }
            
            AirPlayRoutePicker()
                .frame(width: airPlaySize, height: airPlaySize)
                .accessibilityLabel("AirPlay and output")
            
            if vm.availableViewModes.contains(.overlay) {
                controlButton(systemName: "pip.enter", label: "Picture-in-Picture", size: buttonSize, iconFont: iconFont) {
                    rotateToPortrait()
                    withAnimation {
                        vm.toggleViewMode()
                    }
                }
            }
        }
    }
    
    private func fullscreenTimeline(
        onScrubStarted: (() -> Void)? = nil,
        onScrubEnded: (() -> Void)? = nil
    ) -> some View {
        FullscreenTimeline(
            player: vm.player,
            onScrubStarted: onScrubStarted ?? {
                fullscreenControlsHideTask?.cancel()
                fullscreenControlsHideTask = nil
                fullscreenControlsVisible = true
            },
            onScrubEnded: onScrubEnded ?? {
                scheduleFullscreenControlsAutoHide()
            }
        )
    }
    
    private func detailStreamCenterControls() -> some View {
        fullscreenTransportControls(buttonSize: 38, iconFont: .system(size: 22, weight: .semibold), spacing: 24)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.black.opacity(0.28))
            .clipShape(Capsule())
    }
    
    private func detailStreamBottomControls() -> some View {
        HStack(spacing: 12) {
            fullscreenOutputControls(buttonSize: 28, airPlaySize: 28, spacing: 12, iconFont: .system(size: 17, weight: .semibold))
            controlButton(systemName: "arrow.up.left.and.arrow.down.right", label: "Full Screen", size: 28, iconFont: .system(size: 17, weight: .semibold)) {
                enterDetailStreamRotatedFullscreen()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(fullscreenBottomGradient)
    }
    
    private func fullscreenCenterControls(isLandscape: Bool) -> some View {
        fullscreenTransportControls(
            buttonSize: isLandscape ? 58 : 44,
            iconFont: isLandscape ? .system(size: 34, weight: .semibold) : .system(size: 25, weight: .semibold),
            spacing: isLandscape ? 44 : 28
        )
        .padding(.horizontal, isLandscape ? 26 : 20)
        .padding(.vertical, isLandscape ? 18 : 14)
        .background(.black.opacity(0.28))
        .clipShape(Capsule())
    }
    
    private func fullscreenTransportControls(buttonSize: CGFloat, iconFont: Font, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            controlButton(systemName: "gobackward.10", label: "Back 10 Seconds", size: buttonSize, iconFont: iconFont) {
                vm.seekBackward()
            }
            .disabled(!hasSeekableDuration)
            .opacity(hasSeekableDuration ? 1.0 : 0.35)
            
            if vm.didFinishPlaying {
                controlButton(systemName: "memories", label: "Replay", size: buttonSize, iconFont: iconFont) {
                    vm.replay()
                }
            }
            else {
                controlButton(systemName: vm.isPlaying ? "pause.fill" : "play.fill", label: vm.isPlaying ? "Pause" : "Play", size: buttonSize, iconFont: iconFont) {
                    togglePlayPause()
                }
            }
            
            controlButton(systemName: "goforward.10", label: "Forward 10 Seconds", size: buttonSize, iconFont: iconFont) {
                vm.seekForward()
            }
            .disabled(!hasSeekableDuration || vm.didFinishPlaying)
            .opacity(hasSeekableDuration && !vm.didFinishPlaying ? 1.0 : 0.35)
        }
    }
    
    private var fullscreenBottomGradient: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.7)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private func topControlsTopPadding(geometry: GeometryProxy, isLandscape: Bool) -> CGFloat {
        let base: CGFloat
        if isLandscape {
            base = max(geometry.safeAreaInsets.top, 8)
        }
        else {
            let windowTopInset = activeWindowScene()?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.top ?? 0
            base = max(geometry.safeAreaInsets.top, windowTopInset, 8)
        }
        // Mac Catalyst hides the title bar but keeps traffic lights over the top-left content area.
        // Push fullscreen chrome down so Close (xmark) remains tappable.
        if IS_CATALYST {
            return base + 28
        }
        return base
    }
    
    private func fullscreenTopControls(geometry: GeometryProxy, isLandscape: Bool) -> some View {
        HStack(spacing: 16) {
            controlButton(systemName: "xmark", label: "Close") {
                rotateToPortrait()
                withAnimation {
                    vm.close()
                }
            }
            
            Spacer()
            
            if vm.nrPost != nil, vm.availableViewModes.contains(.overlay) {
                controlButton(systemName: bookmarkState ? "bookmark.fill" : "bookmark", label: "Bookmark") {
                    bookmarkState.toggle()
                }
            }
            
            if !vm.isStream {
                Menu(content: {
                    Button("Save to Photo Library", systemImage: "square.and.arrow.down") {
                        saveAVAssetToPhotos()
                    }
                    .help("Save to Photo Library")
                    Button("Copy video URL", systemImage: "document.on.document") {
                        if let url = vm.currentlyPlayingUrl {
                            UIPasteboard.general.string = url
                            sendNotification(.anyStatus, ("Video URL copied to clipboard", "APP_NOTICE"))
                        }
                    }
                    .help("Copy video URL")
                }, label: {
                    if isSaving {
                        HStack(spacing: 4) {
                            ProgressView()
                            Text(vm.downloadProgress, format: .percent)
                                .font(.caption.monospacedDigit())
                        }
                        .foregroundColor(.white)
                        .tint(.white)
                        .frame(height: 32)
                    }
                    else if didSave {
                        Image(systemName: "square.and.arrow.down.badge.checkmark.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                    }
                    else {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                    }
                })
                .disabled(isSaving)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, max(geometry.safeAreaInsets.leading, geometry.safeAreaInsets.trailing, 12))
        .padding(.top, topControlsTopPadding(geometry: geometry, isLandscape: isLandscape))
        .padding(.bottom, 28)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.7), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    /// Fullscreen chrome only — shares the single AVPlayerViewController from the main player slot.
    /// (A second AVPC for fullscreen was introduced with custom controls and broke device reopen.)
    private func fullscreenChromeOverlays(geometry: GeometryProxy) -> some View {
        let isLandscape = isRotatedFullscreen || geometry.size.width > geometry.size.height
        
        return Color.clear
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleFullscreenControls()
            }
            .overlay(alignment: .top) {
                if fullscreenControlsVisible {
                    fullscreenTopControls(geometry: geometry, isLandscape: isLandscape)
                }
            }
            .overlay(alignment: .center) {
                if fullscreenControlsVisible && !shouldShowPlaybackSpinner {
                    fullscreenCenterControls(isLandscape: isLandscape)
                }
            }
            .overlay(alignment: .bottom) {
                if fullscreenControlsVisible {
                    fullscreenControls(isLandscape: isLandscape)
                }
            }
            .gesture(DragGesture(minimumDistance: 3.0, coordinateSpace: .local)
                .onEnded({ value in
                    if value.translation.height > 0 {
                        rotateToPortrait()
                        vm.close()
                    }
                }))
            .ignoresSafeArea()
    }
    
    private func controlButton(systemName: String, label: String, size: CGFloat = 32, iconFont: Font = .title3, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(iconFont)
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        GeometryReader { geometry in
            if vm.isShown {
                ZStack(alignment: videoAlignment) {
                    // Fullscreen custom chrome sits above the single shared player (no second AVPC).
                    if vm.viewMode == .fullscreen {
                        fullscreenChromeOverlays(geometry: geometry)
                            .zIndex(1)
                    }
                    
                    VStack(spacing: 0) {
                        NRNavigationStack {
                            VStack(spacing: 0) {
                                // -- MARK: Actual video/stream — ONE AVPlayerViewController for all modes
                                // (Pre-custom-controls architecture. Dual AVPCs broke device reopen.)
                                Color.black
                                    .overlay {
                                        if !vm.isLoading {
                                            AVPlayerViewControllerRepresentable(player: $vm.player, isPlaying: $vm.isPlaying, showsPlaybackControls: $vm.showsPlaybackControls, viewMode: $vm.viewMode)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        }
                                    }
                                    .overlay {
                                        if shouldShowPlaybackSpinner {
                                            ProgressView()
                                                .tint(.white)
                                                .controlSize(.large)
                                                .allowsHitTesting(false)
                                        }
                                    }
                                    .frame(
                                        width: vm.viewMode == .fullscreen ? geometry.size.width : nil,
                                        height: vm.viewMode == .fullscreen ? geometry.size.height : nil
                                    )
                                    .frame(maxHeight: avPlayerHeight(geometry: geometry))
                                    .clipped()
                                    .ignoresSafeAreaIfFullscreen(vm.viewMode)
                                    .animation(.smooth, value: vm.viewMode)
                                    .overlay { // MARK: Overlay after finished playing
                                        if vm.didFinishPlaying {
                                            ZStack {
                                                Color.black.opacity(0.75)
                                                    .gesture(DragGesture(minimumDistance: 3.0, coordinateSpace: .local)
                                                        .onEnded({ value in
                                                            // close on swipe down
                                                            if value.translation.height > 0 {
                                                                if vm.viewMode == .fullscreen {
                                                                    rotateToPortrait()
                                                                }
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
                                                            EmojiButton(nrPost: nrPost, isFirst: true, isLast: false, theme: theme)
                                                                .foregroundColor(theme.footerButtons)
                                                            if IS_NOT_APPSTORE { // Only available in non app store version
                                                                ZapButton(nrPost: nrPost, isFirst: false, isLast: false, theme: theme)
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
                                    
                                    // Need high priority gesture, else cannot go from .overlay to .fullscreen
                                    // but in .fullscreen we don't need high priority gesture because it interferes with playback controls
                                    // so use custom .highPriorityGestureIf()
                                    // but with this cannot tap like button, so only do when  !vm.didFinishPlaying
//                                    .onTapGesture {
//                                        withAnimation {
//                                            vm.toggleViewMode()
//                                        }
//                                    }
                                    .highPriorityGestureIf(condition: vm.viewMode == .overlay && !vm.didFinishPlaying, gesture: TapGesture()
                                            .onEnded {
                                                withAnimation {
                                                    vm.toggleViewMode()
                                                }
                                        }
                                    )
                                
                                
                                    .overlay(alignment: .topLeading) {
                                        if vm.viewMode == .overlay {
                                            Image(systemName: "xmark")
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
                                    // Transparent hit layer so taps reach SwiftUI even when AVPlayerViewController eats touches.
                                    // Control overlays below stay on top and remain interactive.
                                    // Skip when finished so the replay / like overlay can receive taps.
                                    .overlay {
                                        if vm.viewMode == .detailstream, !vm.didFinishPlaying {
                                            Color.clear
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    toggleDetailStreamControls()
                                                }
                                        }
                                    }
                                    .overlay(alignment: .center) {
                                        if shouldShowDetailStreamVideoControls {
                                            detailStreamCenterControls()
                                        }
                                    }
                                    .overlay(alignment: .bottomTrailing) {
                                        if shouldShowDetailStreamVideoControls {
                                            detailStreamBottomControls()
                                        }
                                    }
                                
                                    .onDisappear {
                                        // Restore normal idle behavior
                                        UIApplication.shared.isIdleTimerDisabled = false
                                        
                                        // Cancel any ongoing tasks when view disappears
                                        AnyPlayerModel.shared.nowPlayingThumbTask?.cancel()
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
                                        Button("Close", systemImage: "xmark") {
                                            withAnimation {
                                                vm.close()
                                            }
                                        }
//                                        .buttonStyle(.borderless)
                                        .foregroundColor(theme.accent)
                                    }
                                }
                                
                                // SAVE BUTTON
                                ToolbarItem(placement: .topBarTrailing) {
                                    if !vm.isStream && vm.viewMode == .detailstream {
                                        Menu(content: {
                                            Button("Save to Photo Library", systemImage: "square.and.arrow.down") {
                                                saveAVAssetToPhotos()
                                            }
                                            .tint(Color.white)
                                            .foregroundColor(theme.accent)
                                            
                                            Button("Copy video URL", systemImage: "document.on.document") {
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
                            }
                        }
                        .introspect(.navigationStack, on: .iOS(.v16...)) {
                            $0.viewControllers.forEach { controller in
                                controller.view.backgroundColor = .clear
                            }
                        }
                        
                        // MARK: Custom video controls
                        if vm.viewMode == .overlay {
                            overlayControls
                        }
                        else if vm.viewMode == .audioOnlyBar {
                            AudioOnlyBar()
                        }
                    }
                    .ultraThinMaterialIfDetail(vm.viewMode)
                    .frame(
                        width: frameWidth(geometry: geometry),
                        height: frameHeight(geometry: geometry)
                    )
                    .ignoresSafeAreaIfFullscreen(vm.viewMode)
                    .ignoresBottomSafeAreaIfDetail(vm.viewMode)
                    .offset(
                        x: clampedOffsetX(geometry: geometry),
                        y: clampedOffsetY(geometry: geometry) - (vm.viewMode == .overlay ? CONTROLS_HEIGHT : 0)
                    )
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
                .onChange(of: vm.viewMode) { _ in
                    if vm.viewMode != .overlay && scale != 1.0 {
                        scale = 1.0
                    }
                    if vm.viewMode == .fullscreen {
                        cancelDetailStreamControlsAutoHide()
                        applyFullscreenControlsForPlaybackState()
                    }
                    else {
                        fullscreenControlsHideTask?.cancel()
                        fullscreenControlsHideTask = nil
                        fullscreenControlsVisible = false
                        restoreAllowedOrientations()
                        if vm.viewMode == .detailstream {
                            applyDetailStreamControlsForPlaybackState()
                        }
                        else {
                            cancelDetailStreamControlsAutoHide()
                            detailStreamControlsVisible = false
                        }
                    }
                }
                .onChange(of: vm.isPlaying) { _ in
                    applyChromeForActualPlayback()
                }
                .onChange(of: vm.timeControlStatus) { _ in
                    applyChromeForActualPlayback()
                }
                .onChange(of: vm.isLoading) { _ in
                    if !vm.isLoading {
                        applyFullscreenControlsForPlaybackState()
                        applyDetailStreamControlsForPlaybackState()
                    }
                    else {
                        hideFullscreenControls()
                        hideDetailStreamControls()
                    }
                }
                .onChange(of: vm.didFinishPlaying) { _ in
                    if vm.didFinishPlaying {
                        showFullscreenControls()
                        showDetailStreamControls()
                    }
                }
                
                
                .onAppear {
                    syncMutedState()
                    applyFullscreenControlsForPlaybackState()
                    applyDetailStreamControlsForPlaybackState()
                    if IS_CATALYST {
                        syncNativeMacFullScreenState()
                    }
                    
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
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NSWindowDidEnterFullScreenNotification"))) { _ in
                    guard IS_CATALYST else { return }
                    isNativeMacFullScreen = true
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NSWindowDidExitFullScreenNotification"))) { _ in
                    guard IS_CATALYST else { return }
                    isNativeMacFullScreen = false
                    enteredNativeMacFullScreenFromPlayer = false
                }
                .onDisappear {
                    fullscreenControlsHideTask?.cancel()
                    fullscreenControlsHideTask = nil
                    cancelDetailStreamControlsAutoHide()
                    shouldRestoreDetailStreamAfterRotatedFullscreen = false
                    if vm.viewMode == .fullscreen {
                        rotateToPortrait()
                    }
                    else {
                        restoreAllowedOrientations()
                        // Leaving non-fullscreen modes should still restore Mac window if we fullscreened it.
                        exitNativeMacFullScreenFromPlayerIfNeeded()
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
    }
    
    /// Clamps a value between a minimum and maximum.
    private func clamp(value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        return Swift.max(min, Swift.min(max, value))
    }
    
    private func frameWidth(geometry: GeometryProxy) -> CGFloat {
        if vm.viewMode == .fullscreen || vm.viewMode == .detailstream {
            return geometry.size.width
        }
        return videoWidth * currentScale
    }
    
    private func frameHeight(geometry: GeometryProxy) -> CGFloat {
        if vm.viewMode == .fullscreen || vm.viewMode == .detailstream {
            return geometry.size.height
        }
        return frameHeight
    }
    
    private func avPlayerHeight(geometry: GeometryProxy) -> CGFloat {
        if vm.viewMode == .fullscreen {
            return geometry.size.height
        }
        return avPlayerHeight
    }
    
    /// Calculates the clamped X offset to ensure the video stays within horizontal bounds.
    private func clampedOffsetX(geometry: GeometryProxy) -> CGFloat {
        if vm.viewMode == .detailstream { return 0 }
        if vm.viewMode == .fullscreen { return 0 }
        if vm.viewMode == .audioOnlyBar {
            if IS_DESKTOP_COLUMNS() {
                return SIDEBAR_WIDTH
            }
            return 0
        }
        
        let totalWidth = videoWidth * currentScale + 2
        let maxOffsetX = geometry.size.width - totalWidth
        return clamp(value: currentOffset.width + dragOffset.width, min: 0, max: maxOffsetX)
    }
    
    /// Calculates the clamped Y offset to ensure the video stays within vertical bounds.
    private func clampedOffsetY(geometry: GeometryProxy) -> CGFloat {
        if vm.viewMode == .detailstream { return 0 }
        if vm.viewMode == .fullscreen { return 0 }
        if vm.viewMode == .audioOnlyBar {
            if IS_DESKTOP_COLUMNS() {
                return ScreenSpace.shared.mainTabSize.height - AUDIOONLYPILL_HEIGHT
            }
            return ScreenSpace.shared.screenSize.height - 98.0
        }
        
        let maxOffsetY = geometry.size.height - (videoHeight * currentScale)
        return clamp(value: currentOffset.height + dragOffset.height, min: 0, max: maxOffsetY)
    }
    
    private func togglePlayPause() {
        if vm.isPlaying {
            vm.pauseVideo()
            showFullscreenControls()
            showDetailStreamControls()
        }
        else {
            vm.playVideo()
            // Chrome hides once timeControlStatus becomes .playing
        }
    }
    
    /// Hide chrome only when the player is actually playing, not merely when play was requested.
    /// Otherwise a stuck autoplay leaves controls hidden and pause/play unreachable.
    private func applyChromeForActualPlayback() {
        if vm.isLoading {
            hideFullscreenControls()
            hideDetailStreamControls()
            return
        }
        if vm.timeControlStatus == .playing, !vm.didFinishPlaying {
            hideFullscreenControls()
            hideDetailStreamControls()
        }
        else {
            showFullscreenControls()
            showDetailStreamControls()
        }
    }
    
    private func toggleFullscreenControls() {
        fullscreenControlsVisible.toggle()
        if fullscreenControlsVisible {
            scheduleFullscreenControlsAutoHide()
        }
        else {
            hideFullscreenControls()
        }
    }
    
    /// Show chrome only when paused/finished; keep it hidden while loading or actually playing.
    private func applyFullscreenControlsForPlaybackState() {
        guard vm.viewMode == .fullscreen else { return }
        if vm.isLoading || (vm.timeControlStatus == .playing && !vm.didFinishPlaying) {
            hideFullscreenControls()
        }
        else {
            showFullscreenControls()
        }
    }
    
    private func showFullscreenControls() {
        guard vm.viewMode == .fullscreen else { return }
        fullscreenControlsVisible = true
        scheduleFullscreenControlsAutoHide()
    }
    
    private func hideFullscreenControls() {
        fullscreenControlsHideTask?.cancel()
        fullscreenControlsHideTask = nil
        fullscreenControlsVisible = false
    }
    
    private func scheduleFullscreenControlsAutoHide() {
        fullscreenControlsHideTask?.cancel()
        // Auto-hide in any fullscreen orientation (portrait + landscape), not only after rotate button.
        guard vm.viewMode == .fullscreen, fullscreenControlsVisible, vm.isPlaying, !vm.didFinishPlaying else { return }
        fullscreenControlsHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if vm.viewMode == .fullscreen, vm.isPlaying, !vm.didFinishPlaying {
                    fullscreenControlsVisible = false
                }
            }
        }
    }
    
    private func toggleDetailStreamControls() {
        detailStreamControlsVisible.toggle()
        if detailStreamControlsVisible {
            scheduleDetailStreamControlsAutoHide()
        }
        else {
            hideDetailStreamControls()
        }
    }
    
    /// Show chrome only when paused/finished; keep it hidden while loading or actually playing.
    private func applyDetailStreamControlsForPlaybackState() {
        guard vm.viewMode == .detailstream else { return }
        if vm.isLoading || (vm.timeControlStatus == .playing && !vm.didFinishPlaying) {
            hideDetailStreamControls()
        }
        else {
            showDetailStreamControls()
        }
    }
    
    private func showDetailStreamControls() {
        guard vm.viewMode == .detailstream else { return }
        detailStreamControlsVisible = true
        scheduleDetailStreamControlsAutoHide()
    }
    
    private func hideDetailStreamControls() {
        detailStreamControlsHideTask?.cancel()
        detailStreamControlsHideTask = nil
        detailStreamControlsVisible = false
    }
    
    private func scheduleDetailStreamControlsAutoHide() {
        detailStreamControlsHideTask?.cancel()
        guard vm.viewMode == .detailstream, detailStreamControlsVisible, vm.isPlaying, !vm.didFinishPlaying else { return }
        detailStreamControlsHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if vm.viewMode == .detailstream, vm.isPlaying, !vm.didFinishPlaying {
                    detailStreamControlsVisible = false
                }
            }
        }
    }
    
    private func cancelDetailStreamControlsAutoHide() {
        detailStreamControlsHideTask?.cancel()
        detailStreamControlsHideTask = nil
    }
    
    private func enterDetailStreamRotatedFullscreen() {
        shouldRestoreDetailStreamAfterRotatedFullscreen = true
        vm.viewMode = .fullscreen
        if IS_CATALYST {
            // Real macOS window full screen — not iOS landscape rotation.
            enterNativeMacFullScreenFromPlayer()
        }
        else {
            rotateToLandscape()
        }
    }
    
    private func rotateToLandscape() {
        if IS_CATALYST {
            // Orientation APIs are iOS-only; on Mac use native window full screen.
            if vm.viewMode != .fullscreen, vm.availableViewModes.contains(.fullscreen) {
                vm.viewMode = .fullscreen
            }
            enterNativeMacFullScreenFromPlayer()
            return
        }
        if vm.viewMode != .fullscreen, vm.availableViewModes.contains(.fullscreen) {
            vm.viewMode = .fullscreen
        }
        isRotatedFullscreen = true
        applyFullscreenControlsForPlaybackState()
        
        AppDelegate.supportedOrientations = .landscapeRight
        refreshSupportedOrientations()
        UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        UINavigationController.attemptRotationToDeviceOrientation()
        
        guard let windowScene = activeWindowScene() else { return }
        
        if #available(iOS 16.0, *) {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { error in
#if DEBUG
                L.og.debug("Landscape rotation request failed: \(error.localizedDescription)")
#endif
            }
        }
    }
    
    private func rotateToPortrait() {
        isRotatedFullscreen = false
        if vm.viewMode == .fullscreen {
            applyFullscreenControlsForPlaybackState()
        }
        else {
            hideFullscreenControls()
        }
        
        if IS_CATALYST {
            exitNativeMacFullScreenFromPlayerIfNeeded()
        }
        else {
            AppDelegate.supportedOrientations = .allButUpsideDown
            refreshSupportedOrientations()
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
            UINavigationController.attemptRotationToDeviceOrientation()
            
            if let windowScene = activeWindowScene(), #available(iOS 16.0, *) {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { error in
#if DEBUG
                    L.og.debug("Portrait rotation request failed: \(error.localizedDescription)")
#endif
                }
            }
        }
        
        if shouldRestoreDetailStreamAfterRotatedFullscreen {
            shouldRestoreDetailStreamAfterRotatedFullscreen = false
            vm.viewMode = .detailstream
        }
    }
    
    private func restoreAllowedOrientations() {
        if IS_CATALYST {
            isRotatedFullscreen = false
            return
        }
        isRotatedFullscreen = false
        AppDelegate.supportedOrientations = .allButUpsideDown
        refreshSupportedOrientations()
    }
    
    private func activeWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
    }
    
    private func refreshSupportedOrientations() {
        if #available(iOS 16.0, *) {
            activeWindowScene()?.windows.first(where: { $0.isKeyWindow })?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        else {
            UINavigationController.attemptRotationToDeviceOrientation()
        }
    }
    
    // MARK: - Native macOS window full screen (Mac Catalyst)
    
    /// NSWindow.StyleMask.fullScreen raw value (`1 << 14`).
    private static let nsWindowFullScreenStyleMask: UInt = 1 << 14
    
    private func keyMacNSWindow() -> NSObject? {
        guard IS_CATALYST else { return nil }
        guard let appClass = NSClassFromString("NSApplication") as? NSObject.Type else { return nil }
        let sharedSelector = NSSelectorFromString("sharedApplication")
        guard appClass.responds(to: sharedSelector),
              let nsApp = appClass.perform(sharedSelector)?.takeUnretainedValue() as? NSObject
        else { return nil }
        
        if let keyWindow = nsApp.value(forKey: "keyWindow") as? NSObject {
            return keyWindow
        }
        if let mainWindow = nsApp.value(forKey: "mainWindow") as? NSObject {
            return mainWindow
        }
        return (nsApp.value(forKey: "windows") as? [NSObject])?.first
    }
    
    private func isMacWindowInFullScreen() -> Bool {
        guard let window = keyMacNSWindow(),
              let styleMask = window.value(forKey: "styleMask") as? UInt
        else { return false }
        return styleMask & Self.nsWindowFullScreenStyleMask != 0
    }
    
    private func performMacWindowToggleFullScreen() {
        guard let window = keyMacNSWindow() else { return }
        let selector = NSSelectorFromString("toggleFullScreen:")
        guard window.responds(to: selector) else { return }
        window.perform(selector, with: nil)
    }
    
    private func syncNativeMacFullScreenState() {
        guard IS_CATALYST else { return }
        isNativeMacFullScreen = isMacWindowInFullScreen()
        if !isNativeMacFullScreen {
            enteredNativeMacFullScreenFromPlayer = false
        }
    }
    
    private func enterNativeMacFullScreenFromPlayer() {
        guard IS_CATALYST else { return }
        syncNativeMacFullScreenState()
        guard !isNativeMacFullScreen else { return }
        enteredNativeMacFullScreenFromPlayer = true
        performMacWindowToggleFullScreen()
        // Notifications update state; also resync shortly after the animation starts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            syncNativeMacFullScreenState()
        }
    }
    
    private func exitNativeMacFullScreenFromPlayerIfNeeded() {
        guard IS_CATALYST else { return }
        syncNativeMacFullScreenState()
        guard enteredNativeMacFullScreenFromPlayer, isNativeMacFullScreen else { return }
        performMacWindowToggleFullScreen()
        enteredNativeMacFullScreenFromPlayer = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            syncNativeMacFullScreenState()
        }
    }
    
    private func toggleNativeMacFullScreenFromPlayer() {
        guard IS_CATALYST else { return }
        syncNativeMacFullScreenState()
        if isNativeMacFullScreen {
            // Exit whether we or the user entered full screen — explicit toggle.
            if enteredNativeMacFullScreenFromPlayer {
                exitNativeMacFullScreenFromPlayerIfNeeded()
            }
            else {
                performMacWindowToggleFullScreen()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    syncNativeMacFullScreenState()
                }
            }
        }
        else {
            enterNativeMacFullScreenFromPlayer()
        }
    }
    
    private func syncMutedState() {
        isMuted = vm.player.isMuted
    }
    
    private func toggleMute() {
        vm.player.isMuted.toggle()
        syncMutedState()
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

private struct FullscreenTimeline: View {
    let player: AVPlayer
    let onScrubStarted: () -> Void
    let onScrubEnded: () -> Void
    
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var timeObserverToken: Any?
    
    private var hasSeekableDuration: Bool {
        duration.isFinite && duration > 0
    }
    
    private var remainingTime: Double {
        guard hasSeekableDuration else { return 0 }
        return max(duration - currentTime, 0)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Text(formatPlaybackTime(currentTime))
                .font(.caption.monospacedDigit())
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 46, alignment: .leading)
            
            Slider(
                value: Binding(
                    get: { min(currentTime, max(duration, 0)) },
                    set: { newValue in
                        isScrubbing = true
                        currentTime = newValue
                    }
                ),
                in: 0...max(duration, 1),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if editing {
                        onScrubStarted()
                    }
                    else {
                        seek(to: currentTime)
                        onScrubEnded()
                    }
                }
            )
            .tint(.white)
            .disabled(!hasSeekableDuration)
            
            Text(hasSeekableDuration ? "-\(formatPlaybackTime(remainingTime))" : "--:--")
                .font(.caption.monospacedDigit())
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 52, alignment: .trailing)
        }
        .onAppear {
            syncPlaybackValues()
            setupTimeObserver()
        }
        .onDisappear {
            removeTimeObserver()
        }
    }
    
    private func setupTimeObserver() {
        guard timeObserverToken == nil else { return }
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { _ in
            syncPlaybackValues()
        }
    }
    
    private func removeTimeObserver() {
        guard let timeObserverToken else { return }
        player.removeTimeObserver(timeObserverToken)
        self.timeObserverToken = nil
    }
    
    private func syncPlaybackValues() {
        let currentSeconds = player.currentTime().seconds
        if !isScrubbing, currentSeconds.isFinite {
            currentTime = max(currentSeconds, 0)
        }
        
        let durationSeconds = player.currentItem?.duration.seconds ?? 0
        duration = durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : 0
    }
    
    private func seek(to seconds: Double) {
        guard hasSeekableDuration else { return }
        let clampedSeconds = min(max(seconds, 0), duration)
        AnyPlayerModel.shared.didFinishPlaying = false
        player.seek(to: CMTime(seconds: clampedSeconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC)))
    }
    
    private func formatPlaybackTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.prioritizesVideoDevices = true
        routePickerView.tintColor = .white
        routePickerView.activeTintColor = .white
        routePickerView.backgroundColor = .clear
        return routePickerView
    }
    
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = .white
        uiView.activeTintColor = .white
    }
}

extension View {
    
    @ViewBuilder
    func ignoresSafeAreaIfFullscreen(_ viewMode: AnyPlayerViewMode) -> some View {
        if viewMode == .fullscreen {
            self.ignoresSafeArea()
        }
        else {
            self
        }
    }
    
    @ViewBuilder
    func ignoresBottomSafeAreaIfDetail(_ viewMode: AnyPlayerViewMode) -> some View {
        if viewMode == .detailstream {
            self.ignoresSafeArea(.container, edges: .bottom)
        }
        else {
            self
        }
    }
    
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
