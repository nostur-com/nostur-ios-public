//
//  ComposePostCompat.swift
//  Nostur
//
//  Created by Fabian Lachman on 17/04/2025.
//

import SwiftUI

struct ComposePostCompat: View {
    public var replyTo: ReplyTo? = nil
    public var quotePost: QuotePost? = nil
    public var directMention: NRContact? = nil // For initiating a post from profile view
    public var onDismiss: () -> Void
    public var kind: NEventKind? = nil
    public var highlight: NewHighlight? = nil
    
    var body: some View {
        if #available(iOS 16.0, *) {
            ComposePost(replyTo: replyTo, quotePost: quotePost, directMention: directMention, onDismiss: onDismiss, kind: kind, highlight: highlight)
        }
        else {
            ComposePost15(replyTo: replyTo, quotePost: quotePost, directMention: directMention, onDismiss: onDismiss, highlight: highlight) // No image picker yet on iOS 15 so remove kind:20 detection
        }
    }
}
