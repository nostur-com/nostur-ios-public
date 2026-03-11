//
//  SendPostIntent.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/03/2026.
//

import AppIntents
import Foundation
import UIKit

@available(iOS 16.0, macCatalyst 16.0, *)
struct SendPostIntent: AppIntent {
    
    static var title: LocalizedStringResource = "Send Nostr Post"
    static var description = IntentDescription("Publishes a new post to the Nostr network using your active account.")
    
    @Parameter(title: "Post Text", description: "The text content of the post to publish.")
    var postText: String
    
    @Parameter(title: "Account", description: "The account to post from. Defaults to the currently active account if not specified.")
    var account: NostrAccountEntity?
    
    @Parameter(title: "Images", description: "Optional images to attach to the post. Requires a Blossom server to be configured in Nostur settings.")
    var images: [IntentFile]?
    
    static var parameterSummary: some ParameterSummary {
        Summary("Post \(\.$postText) to Nostr") {
            \.$account
            \.$images
        }
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Resolve the CloudAccount — use selected account, or fall back to active account
        let resolvedAccount: CloudAccount
        if let selectedAccount = account {
            guard let found = AccountsState.shared.fullAccounts.first(where: { $0.publicKey == selectedAccount.id }) else {
                throw SendPostIntentError.accountNotFound
            }
            resolvedAccount = found
        } else {
            guard let active = AccountsState.shared.loggedInAccount?.account else {
                throw SendPostIntentError.noActiveAccount
            }
            guard active.isFullAccount else {
                throw SendPostIntentError.accountCannotPost
            }
            resolvedAccount = active
        }
        
        let account = resolvedAccount
        
        // Upload images if provided
        var imetas: [Imeta] = []
        if let images, !images.isEmpty {
            imetas = try await uploadImages(images, account: account)
        }
        
        // Build the NEvent
        var content = postText
        var tags: [NostrTag] = []
        
        for imeta in imetas {
            // Append image URL to content (same as kind:1 behavior in buildFinalEvent)
            content += "\n\(imeta.url)"
            
            // Add imeta tag
            var imetaParts: [String] = ["imeta", "url \(imeta.url)"]
            if let dim = imeta.dim, !dim.isEmpty {
                imetaParts.append("dim \(dim)")
            }
            if let blurhash = imeta.blurhash, !blurhash.isEmpty {
                imetaParts.append("blurhash \(blurhash)")
            }
            if let hash = imeta.hash, !hash.isEmpty {
                imetaParts.append("sha256 \(hash)")
            }
            tags.append(NostrTag(imetaParts))
        }
        
        var event = NEvent(content: content)
        event.publicKey = account.publicKey
        event.tags = tags
        
        let signedEvent = try account.signEvent(event)
        
        Unpublisher.shared.publishNow(signedEvent)
        
        return .result(value: signedEvent.id)
    }
    
    // Upload images to the user's configured Blossom server and return Imeta metadata
    @MainActor
    private func uploadImages(_ intentFiles: [IntentFile], account: CloudAccount) async throws -> [Imeta] {
        guard let blossomServerString = SettingsStore.shared.blossomServerList.first,
              let blossomServerURL = URL(string: blossomServerString) else {
            throw SendPostIntentError.noBlossomServer
        }
        
        var imetas: [Imeta] = []
        
        for intentFile in intentFiles {
            let data = try intentFile.data
            let contentType = intentFile.type?.preferredMIMEType ?? "image/jpeg"
            
            // Resize if it's an image (same max width as NewPostModel: 2800px)
            let uploadData: Data
            let dim: String?
            let blurhash: String?
            
            if contentType.hasPrefix("image/") && contentType != "image/gif",
               let uiImage = UIImage(data: data) {
                let maxWidth: CGFloat = 2800.0
                let scale = uiImage.size.width > maxWidth ? uiImage.size.width / maxWidth : 1
                let targetSize = CGSize(width: uiImage.size.width / scale, height: uiImage.size.height / scale)
                let resized = uiImage.resized(to: targetSize)
                uploadData = resized.jpegData(compressionQuality: 0.85) ?? data
                dim = "\(Int(resized.size.width))x\(Int(resized.size.height))"
                // Generate blurhash at 32x32 for performance (same as NewPostModel)
                let thumbImage = resized.resized(to: CGSize(width: 32, height: 32))
                blurhash = thumbImage.blurHash(numberOfComponents: (4, 3))
            } else {
                uploadData = data
                if contentType.hasPrefix("image/"),
                   let uiImage = UIImage(data: data) {
                    dim = "\(Int(uiImage.size.width))x\(Int(uiImage.size.height))"
                    let thumbImage = uiImage.resized(to: CGSize(width: 32, height: 32))
                    blurhash = thumbImage.blurHash(numberOfComponents: (4, 3))
                } else {
                    dim = nil
                    blurhash = nil
                }
            }
            
            let blossomFile = BlossomUploadFile(data: uploadData, contentType: contentType)
            let authHeader = try await getBlossomAuthHeader(account: account, blossomFile: blossomFile)
            let downloadUrl = try await blossomUpload(
                authHeader: authHeader,
                blossomFile: blossomFile,
                contentType: contentType,
                blossomServer: blossomServerURL
            )
            
            imetas.append(Imeta(url: downloadUrl, dim: dim, hash: blossomFile.sha256, blurhash: blurhash))
        }
        
        return imetas
    }
}

@available(iOS 16.0, macCatalyst 16.0, *)
enum SendPostIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case noActiveAccount
    case accountCannotPost
    case accountNotFound
    case noBlossomServer
    
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noActiveAccount:
            return "No active Nostr account found. Please log in to Nostur first."
        case .accountCannotPost:
            return "The active account cannot post (it may be a read-only or remote signer account)."
        case .accountNotFound:
            return "The selected account could not be found. It may have been removed."
        case .noBlossomServer:
            return "No Blossom server configured. Please configure a Blossom server in Nostur settings to upload images."
        }
    }
}
