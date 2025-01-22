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
    
    let videoHeight: CGFloat = 100.0
    let videoWidth: CGFloat = 178.0
    let videoPaddingHorizontal: CGFloat = 12.0
    
    // State variables for dragging
    @State private var currentOffset = CGSize(width: 0.0, height: UIScreen.main.bounds.height - 100.0) // Initial Y offset
    @State private var dragOffset = CGSize.zero
    
    // State variables for scaling
    @State private var currentScale: CGFloat = 1.0
    @State private var scale: CGFloat = 1.0
    
    private func tap() {
        switch vm.viewMode {
        case .off:
            vm.viewMode = .overlay
        case .overlay:
            vm.viewMode = .videostream
        case .videostream, .audiostream:
            vm.viewMode = .fullscreen
        case .fullscreen:
            vm.viewMode = .off
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {

                switch vm.viewMode {
                case .off:
                    Text("off")
                        .foregroundColor(Color.red)
                        .onTapGesture {
                            self.tap()
                        }
                case .overlay:
                    VStack(spacing: 0) {
                        //                    Text("haa")
                        //                        .foregroundColor(.white)
                        AVPlayerViewControllerRepresentable(player: $vm.player, isPlaying: $vm.isPlaying)
                            .onTapGesture {
                                self.tap()
                            }
                        HStack(spacing: 20) {
                            Button(action: {
                                self.tap()
                            }) {
                                Image(systemName: "theatermasks")
                                    .foregroundColor(.white)
                                    .font(.title2)
                            }
                            
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
                    .background(Color.black)
                    .frame(
                        width: videoWidth * currentScale,
                        height: (videoHeight * currentScale) + CONTROLS_HEIGHT
                    )
                    .padding(.horizontal, videoPaddingHorizontal)
                    .offset(
                        x: clampedOffsetX(geometry: geometry),
                        y: clampedOffsetY(geometry: geometry) - CONTROLS_HEIGHT
                    )
                    .gesture(
                        // Combine Drag and Magnification Gestures
                        SimultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    self.dragOffset = value.translation
                                }
                                .onEnded { value in
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
                                    self.scale = 1.0
                                }
                        )
                    )
                case .audiostream, .videostream, .fullscreen:
                    VStack(spacing: 0) {
                        AVPlayerViewControllerRepresentable(player: $vm.player, isPlaying: $vm.isPlaying)
                        if (vm.viewMode == .fullscreen) {
                            Text("fullscreen")
                                .foregroundColor(Color.red)
                        }
                        Color.red
                            .frame(height: 400)
                            .onTapGesture {
                                self.tap()
                            }
                    }
                }
            }
        }
//        .onChange(of: viewMode) { euh in
//            scale = 2.0
//        }
    }
    
    /// Clamps a value between a minimum and maximum.
    private func clamp(value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        return Swift.max(min, Swift.min(max, value))
    }
    
    /// Calculates the clamped X offset to ensure the video stays within horizontal bounds.
    private func clampedOffsetX(geometry: GeometryProxy) -> CGFloat {
        let totalWidth = videoWidth * currentScale + 2 * videoPaddingHorizontal
        let maxOffsetX = geometry.size.width - totalWidth
        return clamp(value: currentOffset.width + dragOffset.width, min: 0, max: maxOffsetX)
    }
    
    /// Calculates the clamped Y offset to ensure the video stays within vertical bounds.
    private func clampedOffsetY(geometry: GeometryProxy) -> CGFloat {
        let maxOffsetY = geometry.size.height - (videoHeight * currentScale)
        return clamp(value: currentOffset.height + dragOffset.height, min: 0, max: maxOffsetY)
    }
}
