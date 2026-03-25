//
//  DMFileMessageView.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/03/2026.
//

import SwiftUI
import QuickLook

struct DMFileMessageView: View {
    let fileInfo: FileMessageInfo
    let isSentByCurrentUser: Bool
    let isAccepted: Bool
    
    @State private var decryptedImage: UIImage? = nil
    @State private var isLoading = false
    @State private var error: String? = nil
    @State private var quickLookURL: URL? = nil
    @State private var manuallyTriggered = false
    public var zoomableId: String = "Default"
    
    @Environment(\.theme) private var theme
    
    var body: some View {
        if fileInfo.isImage {
            imageView
        } else {
            documentView
        }
    }
    
    // MARK: - Image View
    
    @ViewBuilder
    private var imageView: some View {
        // Stable outer container — .task lives here so it isn't cancelled by inner state changes
        Group {
            if let decryptedImage {
                ZoomableItem(id: zoomableId) {
                    Image(uiImage: decryptedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 250, maxHeight: 300)
                        .clipShape(.rect(cornerRadius: 8))
                } detailContent: {
                    GalleryFullScreenSwiper(
                        initialIndex: 0,
                        items: [GalleryItem(
                            url: URL(string: fileInfo.url) ?? URL(string: "about:blank")!,
                            imageInfo: ImageInfo(uiImage: decryptedImage, realDimensions: decryptedImage.size)
                        )],
                        isEncrypted: true
                    )
                }
            } else if isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Decrypting...")
                        .font(.caption)
                        .foregroundStyle(isSentByCurrentUser ? .white.opacity(0.7) : .secondary)
                }
                .frame(width: 150, height: 100)
            } else if let error {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(isSentByCurrentUser ? .white.opacity(0.7) : .secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        self.error = nil
                        self.isLoading = true
                        Task { await loadAndDecryptImage() }
                    }
                    .font(.caption2)
                }
                .frame(minWidth: 150, minHeight: 80)
            } else if !isAccepted && !manuallyTriggered {
                // For requests / outside WoT: show a card, tap to decrypt
                Button {
                    manuallyTriggered = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "photo.badge.arrow.down")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Encrypted Image")
                                .font(.footnote.bold())
                            if let size = fileInfo.formattedFileSize {
                                Text(size)
                                    .font(.caption)
                            }
                        }
                    }
                    .foregroundStyle(isSentByCurrentUser ? .white : theme.primary)
                    .padding(10)
                }
            } else {
                // Waiting to auto-load
                Color.gray.opacity(0.2)
                    .frame(width: 150, height: 100)
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay { ProgressView() }
            }
        }
        .task {
            // Only auto-load for accepted chats
            guard isAccepted || manuallyTriggered else { return }
            await loadAndDecryptImage()
        }
        .onChange(of: manuallyTriggered) { triggered in
            guard triggered else { return }
            Task { await loadAndDecryptImage() }
        }
    }
    
    // MARK: - Document View
    
    private var documentView: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: iconForMimeType(fileInfo.mimeType))
                    .font(.title2)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileInfo.displayName)
                        .font(.footnote.bold())
                    if let size = fileInfo.formattedFileSize {
                        Text(size)
                            .font(.caption)
                    }
                    if isLoading {
                        Text("Downloading...")
                            .font(.caption2)
                    }
                }
                
                Spacer(minLength: 0)
                
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                }
            }
            .foregroundStyle(isSentByCurrentUser ? .white : theme.primary)
            .padding(10)
            .frame(maxWidth: 220)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isLoading else { return }
                Task { await downloadAndPreviewDocument() }
            }
            
            if let error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                Button("Retry") {
                    self.error = nil
                    Task { await downloadAndPreviewDocument() }
                }
                .font(.caption2)
            }
        }
        .quickLookPreview($quickLookURL)
    }
    
    // MARK: - Download & Decrypt Logic
    
    private func loadAndDecryptImage() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        
        do {
            let data = try await downloadAndDecrypt()
            guard let image = UIImage(data: data) else {
                self.error = "Invalid image data"
                isLoading = false
                return
            }
            self.decryptedImage = image
        } catch {
            L.og.error("🔴 DMFileMessage loadAndDecryptImage error: \(error) url: \(fileInfo.url)")
            self.error = error.localizedDescription
        }
        isLoading = false
    }
    
    private func downloadAndPreviewDocument() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        
        do {
            let data = try await downloadAndDecrypt()
            
            // Save to temp file for QuickLook
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "dm_file.\(fileInfo.fileExtension)"
            let fileURL = tempDir.appendingPathComponent(fileName)
            try data.write(to: fileURL)
            
            self.quickLookURL = fileURL
        } catch {
            L.og.error("🔴 DMFileMessage downloadAndPreviewDocument error: \(error) url: \(fileInfo.url)")
            self.error = error.localizedDescription
        }
        isLoading = false
    }
    
    private func downloadAndDecrypt() async throws -> Data {
        guard let url = URL(string: fileInfo.url) else {
            throw DMFileError.uploadFailed("Invalid URL: \(fileInfo.url)")
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw DMFileError.uploadFailed("HTTP \(statusCode)")
        }
        
        return try decryptFileFromDM(
            encryptedData: data,
            key: fileInfo.decryptionKey,
            nonce: fileInfo.decryptionNonce
        )
    }
    
    // MARK: - Helpers
    
    private func iconForMimeType(_ mimeType: String) -> String {
        switch mimeType {
        case let t where t.contains("pdf"):
            return "doc.richtext"
        case let t where t.contains("spreadsheet") || t.contains("excel") || t.contains("csv"):
            return "tablecells"
        case let t where t.contains("word") || t.contains("document"):
            return "doc.text"
        case let t where t.contains("zip") || t.contains("archive") || t.contains("compressed"):
            return "doc.zipper"
        case let t where t.contains("text"):
            return "doc.plaintext"
        case let t where t.contains("audio"):
            return "waveform"
        case let t where t.contains("video"):
            return "film"
        default:
            return "doc"
        }
    }
}


