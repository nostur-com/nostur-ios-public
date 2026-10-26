//
//  ComposePostContainer.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/12/2025.
//

import SwiftUI
import NavigationBackport

extension View {
    /// Composer toolbar overflow on iOS 27 needs the native navigation bar.
    @ViewBuilder
    func composerNavigationStackCompat() -> some View {
        if #available(iOS 27.0, *) {
            self.nbUseNavigationStack(.whenAvailable)
        } else {
            self.nbUseNavigationStack(.never)
        }
    }
}

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
