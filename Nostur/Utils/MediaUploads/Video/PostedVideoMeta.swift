//
//  PostedVideoMeta.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/06/2024.
//

import SwiftUI
import AVFoundation

public class PostedVideoMeta: Hashable, Identifiable, Equatable, ObservableObject {
    
    static public func == (lhs: PostedVideoMeta, rhs: PostedVideoMeta) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public let id = UUID()
    @Published var quality: VideoUploadQuality = .automatic
    @Published var uploadState: ComposerMediaUploadState = .idle
    @Published var preparationProgress: Double = 0
    var preparedVideo: PreparedVideo?

    public let index: Int // To keep the correct order in pasted media
    public let videoURL: URL // local file url
    @Published public var thumbnail: UIImage?
    
    init(index: Int, videoURL: URL, thumbnail: UIImage? = nil, preparedVideo: PreparedVideo? = nil) {
        self.index = index
        self.videoURL = videoURL
        self.thumbnail = thumbnail
        self.preparedVideo = preparedVideo
        self.loadThumbnail()
    }
    
    private func loadThumbnail() {
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let asset = AVAsset(url: self.videoURL)
            let firstFrame = await getVideoFirstFrame(asset: asset)
            
            Task { @MainActor in
                self.thumbnail = firstFrame
            }
        }
    }
    
}
