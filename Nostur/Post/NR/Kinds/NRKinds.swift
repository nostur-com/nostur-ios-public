//
//  NRKinds.swift
//  Nostur
//
//  Created by Fabian Lachman on 26/05/2023.
//

import SwiftUI

struct KindFileMetadata {
    var url:String
    var m:String?
    var hash:String?
    var dim:String?
    var blurhash:String?
}

let SUPPORTED_VIEW_KINDS:Set<Int64> = [1,6,9802,30023,99999]

struct AnyKind: View {
    private var nrPost: NRPost
    private var theme:Theme
    
    init(_ nrPost: NRPost, theme: Theme) {
        self.nrPost = nrPost
        self.theme = theme
    }
    
    var body: some View {
        if SUPPORTED_VIEW_KINDS.contains(nrPost.kind) {
            switch nrPost.kind {
                case 99999:
                    let title = nrPost.eventTitle ?? "Untitled"
                    if let eventUrl = nrPost.eventUrl {
                        VideoEventView(title: title, url: eventUrl, summary: nrPost.eventSummary, imageUrl: nrPost.eventImageUrl, autoload: true, theme: theme)
                            .padding(.vertical, 10)
                    }
                    else {
                        EmptyView()
                }
//                case 9735: TODO: ....
//                    ZapReceipt(sats: <#T##Double#>, receiptPubkey: <#T##String#>, fromPubkey: <#T##String#>, from: <#T##Event#>)
                default:
                    EmptyView()
            }
        }
        else {
            UnknownKindView(nrPost: nrPost, theme: theme)
                .padding(.vertical, 10)
        }
    }
}
