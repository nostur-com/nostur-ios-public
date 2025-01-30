//
//  OverlayVideo.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/01/2025.
//

import SwiftUI

struct OverlayVideo: View {
    @ObservedObject var vm: AnyPlayerModel = .shared
    public var onVideoTap: (() -> Void)? = nil
    
    var videoHeight: CGFloat {
        videoWidth / vm.aspect
    }
    
    var videoWidth: CGFloat {
        if vm.viewMode != .overlay {
            return UIScreen.main.bounds.width
        }
        return UIScreen.main.bounds.width * 0.5
    }
    
    let videoPaddingHorizontal: CGFloat = 0.0 // 12.0
    
    // State variables for dragging
    @State private var currentOffset = CGSize(width: 0.0, height: UIScreen.main.bounds.height - 100.0) // Initial Y offset
    @State private var dragOffset = CGSize(width: UIScreen.main.bounds.width * 0.5, height: .zero)
    
    // State variables for scaling
    @State private var currentScale: CGFloat = 1.0
    @State private var scale: CGFloat = 1.0
    
    private var videoAlignment: Alignment {
        if vm.viewMode == .fullscreen { return .center }
        return .topLeading
    }
        
    // State variables for saving video
    @State private var isSaving = false
    @State private var didSave = false
    
    var body: some View {
        GeometryReader { geometry in
            if vm.cachedVideo != nil {
                ZStack(alignment: videoAlignment) {
                    Color.black.opacity(vm.viewMode == .fullscreen ? 1.0 : 0.0)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "pip.enter")
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
                                                .offset(y: -2)
                                        }
                                    }, primaryAction: saveAVAssetToPhotos)
                                    .disabled(isSaving)
                                .font(.title2)
                                .foregroundColor(Color.white)
                                .padding(.top, 15)
                                .padding(.trailing, 15)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation {
                                        vm.toggleViewMode()
                                    }
                                }
                                .opacity(vm.availableViewModes.contains(.overlay) && vm.viewMode == .fullscreen ? 1.0 : 0)
                        }

                    VStack(spacing: 0) {
                        AVPlayerViewControllerRepresentable(player: $vm.player, isPlaying: $vm.isPlaying, showsPlaybackControls: $vm.showsPlaybackControls, viewMode: $vm.viewMode)
                            .highPriorityGesture(
                                TapGesture()
                                    .onEnded { _ in
                                        withAnimation {
                                            vm.toggleViewMode()
                                        }
                                    }
                            )
//                            .onTapGesture {
//                                withAnimation {
//                                    vm.toggleViewMode()
//                                }
//                            }
                            .padding(.top, vm.viewMode == .fullscreen ? 30.0 : 0.0)
                            .overlay(alignment: .topLeading) {
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
                        if vm.viewMode == .overlay {
                            HStack(spacing: 20) {
                                Button(action: {
                                    vm.seekBackward()
                                }) {
                                    Image(systemName: "gobackward.15")
                                        .foregroundColor(.white)
                                        .font(.title2)
                                }
                                
                                Button(action: {
                                    if vm.isPlaying {
                                        vm.pauseVideo()
                                    }
                                    else {
                                        vm.playVideo()
                                    }
                                }) {
                                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                                        .foregroundColor(.white)
                                        .font(.title)
                                }
                                
                                Button(action: {
                                    vm.seekForward()
                                }) {
                                    Image(systemName: "goforward.15")
                                        .foregroundColor(.white)
                                        .font(.title2)
                                }
                            }
                            .frame(height: CONTROLS_HEIGHT)
                        }
                    }
                    .background(Color.black)
                    .frame(
                        width: videoWidth * currentScale,
                        height: (videoHeight * currentScale) + (vm.viewMode == .overlay ? CONTROLS_HEIGHT : 0)
                    )
    //                    .padding(.horizontal, videoPaddingHorizontal)
                    .offset(
                        x: clampedOffsetX(geometry: geometry),
                        y: clampedOffsetY(geometry: geometry) - CONTROLS_HEIGHT
                    )
                    .gesture(
                        // Combine Drag and Magnification Gestures
                        SimultaneousGesture(
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
                                        max: geometry.size.width - (videoWidth * currentScale + 2 * videoPaddingHorizontal)
                                    )
                                    currentOffset.height = clamp(
                                        value: newOffsetY,
                                        min: 0,
                                        max: geometry.size.height - (videoHeight * currentScale)
                                    )
                                    dragOffset = .zero
                                },
                            MagnificationGesture()
                                .onChanged { value in
                                    guard vm.viewMode == .overlay else { return }
                                    let delta = value / self.scale
                                    self.scale = value
                                    var newScale = self.currentScale * delta
                                    
                                    // Calculate maximum and minimum scales based on geometry
                                    let maxScaleWidth = geometry.size.width / videoWidth
                                    let maxScaleHeight = geometry.size.height / videoHeight
                                    let maxScale = min(maxScaleWidth, maxScaleHeight, 3.0) // 3.0 is an arbitrary upper limit
                                    let minScale: CGFloat = 0.5 // 50% of original size
                                    
                                    // Clamp the new scale
                                    newScale = clamp(value: newScale, min: minScale, max: maxScale)
                                    
                                    self.currentScale = newScale
                                    
                                    // Adjust currentOffset to ensure the video stays within bounds after scaling
                                    currentOffset.width = clamp(
                                        value: currentOffset.width,
                                        min: 0,
                                        max: geometry.size.width - (videoWidth * currentScale + 2 * videoPaddingHorizontal)
                                    )
                                    currentOffset.height = clamp(
                                        value: currentOffset.height,
                                        min: 0,
                                        max: geometry.size.height - (videoHeight * currentScale)
                                    )
                                }
                                .onEnded { _ in
                                    guard vm.viewMode == .overlay else { return }
                                    self.scale = 1.0
                                }
                        )
                    )
                }
                .onChange(of: vm.viewMode) { _ in
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
        
        let totalWidth = videoWidth * currentScale + 2 * videoPaddingHorizontal
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
