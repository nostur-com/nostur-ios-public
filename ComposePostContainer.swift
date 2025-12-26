//
//  ComposePostContainer.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/12/2025.
//

import SwiftUI

struct ComposePostContainer: View {
    
    @Environment(\.dismiss) private var dismiss
    
    public var replyTo: ReplyTo?
    public var quotePost: QuotePost?
    
    @State private var account: CloudAccount? = nil

    var body: some View {
        Container {
            if let account {
                if account.isNC {
                    WithNSecBunkerConnection {
                        ComposePost(replyTo: replyTo, quotePost: quotePost, onDismiss: {
                            dismiss()
                        })
                    }
                }
                else {
                    ComposePost(replyTo: replyTo, quotePost: quotePost, onDismiss: {
                        dismiss()
                    })
                }
            }
            else {
                CenteredProgressView()
            }
        }
        .onAppear {
            guard self.account == nil else { return }
            self.account = Nostur.account()
        }
    }
}

#Preview {
    ComposePostContainer()
}
