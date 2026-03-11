//
//  SendPostIntent.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/03/2026.
//

import AppIntents
import Foundation

@available(iOS 16.0, macCatalyst 16.0, *)
struct SendPostIntent: AppIntent {
    
    static var title: LocalizedStringResource = "Send Nostr Post"
    static var description = IntentDescription("Publishes a new post to the Nostr network using your active account.")
    
    @Parameter(title: "Post Text", description: "The text content of the post to publish.")
    var postText: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("Post \(\.$postText) to Nostr")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let account = AccountsState.shared.loggedInAccount?.account else {
            throw SendPostIntentError.noActiveAccount
        }
        
        guard account.isFullAccount else {
            throw SendPostIntentError.accountCannotPost
        }
        
        var event = NEvent(content: postText)
        event.publicKey = account.publicKey
        
        let signedEvent = try account.signEvent(event)
        
        Unpublisher.shared.publishNow(signedEvent)
        
        return .result(value: signedEvent.id)
    }
}

@available(iOS 16.0, macCatalyst 16.0, *)
enum SendPostIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case noActiveAccount
    case accountCannotPost
    
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noActiveAccount:
            return "No active Nostr account found. Please log in to Nostur first."
        case .accountCannotPost:
            return "The active account cannot post (it may be a read-only or remote signer account)."
        }
    }
}
