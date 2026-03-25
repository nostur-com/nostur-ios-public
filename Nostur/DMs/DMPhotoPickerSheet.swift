//
//  DMPhotoPickerSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/03/2026.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

@available(iOS 16.0, *)
struct DMPhotoPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var isProcessing = false
    
    let onPicked: (_ data: Data, _ mimeType: String, _ dimensions: String?) -> Void
    
    var body: some View {
        NavigationView {
            VStack {
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .any(of: [.images, .videos])
                ) {
                    Label("Select Photo or Video", systemImage: "photo")
                        .font(.headline)
                        .padding()
                }
                
                if isProcessing {
                    ProgressView("Loading...")
                        .padding()
                }
                
                Spacer()
            }
            .navigationTitle("Send Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onChange(of: selectedItem) { newItem in
            guard let newItem else { return }
            isProcessing = true
            Task {
                await processSelectedItem(newItem)
                dismiss()
            }
        }
    }
    
    private func processSelectedItem(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            
            let mimeType: String
            var dimensions: String? = nil
            
            if let contentType = item.supportedContentTypes.first {
                if contentType.conforms(to: .jpeg) {
                    mimeType = "image/jpeg"
                } else if contentType.conforms(to: .png) {
                    mimeType = "image/png"
                } else if contentType.conforms(to: .gif) {
                    mimeType = "image/gif"
                } else if contentType.conforms(to: .webP) {
                    mimeType = "image/webp"
                } else if contentType.conforms(to: .movie) || contentType.conforms(to: .video) {
                    mimeType = "video/mp4"
                } else {
                    mimeType = "application/octet-stream"
                }
            } else {
                mimeType = "image/jpeg"
            }
            
            // Get image dimensions if it's an image
            if mimeType.hasPrefix("image/"), let uiImage = UIImage(data: data) {
                dimensions = "\(Int(uiImage.size.width * uiImage.scale))x\(Int(uiImage.size.height * uiImage.scale))"
            }
            
            onPicked(data, mimeType, dimensions)
        }
        catch {
            L.og.error("🔴 Failed to load photo for DM: \(error)")
        }
    }
}
