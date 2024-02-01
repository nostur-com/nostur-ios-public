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

// We expect to show these properly
let SUPPORTED_VIEW_KINDS: Set<Int64> = [1,6,9802,30023,99999]

// We don't expect to show these, but anyone can quote or reply to any event so we still need to show something
let KNOWN_VIEW_KINDS: Set<Int64> = [0,3,4,5,7,1984,9734,9735,30009,8,30008]

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
        if KNOWN_VIEW_KINDS.contains(nrPost.kind) {
            KnownKindView(nrPost: nrPost, theme: theme)
                .padding(.vertical, 10)
        }
        else {
            UnknownKindView(nrPost: nrPost, theme: theme)
                .padding(.vertical, 10)
        }
    }
}


struct KnownKindView: View {
    @ObservedObject private var settings: SettingsStore = .shared
    @EnvironmentObject private var dim: DIMENSIONS
    @ObservedObject var nrPost: NRPost
    public var hideFooter: Bool = false
    public let theme: Theme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Nostr event")
                    .font(.caption)
                Spacer()
                LazyNoteMenuButton(nrPost: nrPost)
            }
            Text(fallbackDescription(for: nrPost))
                .fontWeightBold()
            
            
            HStack {
                Spacer()
                ZappablePFP(pubkey: nrPost.pubkey, contact: nrPost.contact, size: 25.0, zapEtag: nrPost.id, forceFlat: dim.isScreenshot)
                    .onTapGesture {
                        if let nrContact = nrPost.contact {
                            navigateTo(nrContact)
                        }
                        else {
                            navigateTo(ContactPath(key: nrPost.pubkey))
                        }
                    }
                
                if let contact = nrPost.contact {
                    Text(contact.anyName)
                        .foregroundColor(.primary)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .layoutPriority(2)
                        .onTapGesture {
                            navigateTo(contact)
                        }                }
                else {
                    Text(nrPost.anyName)
                        .onAppear {
                            bg().perform {
                                EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "KnownKindView.001")
                                QueuedFetcher.shared.enqueue(pTag: nrPost.pubkey)
                            }
                        }
                        .onDisappear {
                            QueuedFetcher.shared.dequeue(pTag: nrPost.pubkey)
                        }
                }
                
                Text(nrPost.createdAt.formatted(date: .omitted, time: .shortened))
                Text(nrPost.createdAt.formatted(.dateTime.day().month(.defaultDigits)))
            }
            
            if (!hideFooter && settings.rowFooterEnabled) {
                CustomizableFooterFragmentView(nrPost: nrPost, theme: theme)
                    .background(nrPost.kind == 30023 ? theme.secondaryBackground : theme.background)
                    .drawingGroup(opaque: true)
//                        .withoutAnimation()
//                        .transaction { t in
//                            t.animation = nil
//                        }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

func fallbackDescription(for nrPost: NRPost) -> String {
    return switch nrPost.kind {
    case 0:
        "Profile update"
    case 3:
        "Follow list update"
    case 4:
        "A Direct Message"
    case 5:
        "A deletion request"
    case 7:
        "A reaction"
    case 9734:
        "A zap request"
    case 9735:
        "A zap receipt"
    case 30009:
        "A badge definition update"
    case 8:
        "A badge award"
    case 30008:
        "A profile badge update"
    default:
        "A nostr event of kind: \(nrPost.kind)"
    }
}
