//
//  VineVideoPreview.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/03/2026.
//

import SwiftUI
import AVFoundation

struct VineVideoPreview: View {
    let videoURL: URL
    let duration: Double
    var onRemove: () -> Void
    
    @State private var thumbnail: UIImage?
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 80, height: 120)
                        .overlay { ProgressView() }
                }
                
                // Duration badge
                Text(String(format: "%.1fs", duration))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.7)))
                    .padding(4)
                
                // Play icon overlay
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                    .shadow(radius: 2)
                    .frame(width: 80, height: 120)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Video ready")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(String(format: "%.1f seconds", duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove", systemImage: "trash")
                        .font(.caption)
                }
                .padding(.top, 4)
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .onAppear { generateThumbnail() }
    }
    
    private func generateThumbnail() {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 240)
        
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) { _, cgImage, _, _, _ in
            if let cgImage {
                DispatchQueue.main.async {
                    self.thumbnail = UIImage(cgImage: cgImage)
                }
            }
        }
    }
}
