//
//  NoteRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/03/2023.
//

import SwiftUI

struct NoteRow: View {
    @ObservedObject var nrPost:NRPost
    var hideFooter = true // For rendering in NewReply
    var missingReplyTo = false // For rendering in thread, hide "Replying to.."
    var connect:ThreadConnectDirection? = nil
    let fullWidth:Bool
    let isReply:Bool // is reply on PostDetail (needs 2*10 less box width)
    let isDetail:Bool
    let grouped:Bool
    @EnvironmentObject var dim:DIMENSIONS
    
    private let sp:SocketPool = .shared
    
    init(nrPost:NRPost, hideFooter:Bool = false, missingReplyTo:Bool = false, connect: ThreadConnectDirection? = nil, fullWidth:Bool = false, isReply:Bool = false, isDetail:Bool = false, grouped:Bool = false) {
        self.nrPost = nrPost
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.fullWidth = fullWidth
        self.isReply = isReply
        self.isDetail = isDetail
        self.grouped = grouped
    }
        
    var body: some View {
//        let _ = Self._printChanges()
        VStack (alignment: .leading) {
            if (nrPost.isRepost) {
                HStack(spacing:4) {
                    Image(systemName: "arrow.2.squarepath")
                        .fontWeight(.bold)
                        .scaleEffect(0.6)
                    Text(nrPost.repostedHeader)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .onTapGesture {
                            navigateTo(ContactPath(key: nrPost.pubkey))
                        }
                }
                .foregroundColor(.gray)
                .onTapGesture {
                    navigateTo(ContactPath(key: nrPost.pubkey))
                }
                .padding(.leading, 40)
                .frame(idealHeight: 20.0)
                .padding(.top, 10)
                .fixedSize(horizontal: false, vertical: true)
                // Fixed size for scrolling performance maybe, use to confirm correct size:
//                .readSize { newSize in
//                    print("Repost header size: \(newSize)")
//                }
                
                if let firstQuote = nrPost.firstQuote {
                    // CASE - WE HAVE REPOSTED POST ALREADY
                    if firstQuote.blocked {
                        HStack {
                            Text("_Post from blocked account hidden_", comment: "Message shown when a post is from a blocked account")
                            Button(String(localized: "Reveal", comment: "Button to reveal a blocked a post")) {
                                nrPost.unblockFirstQuote()
                            }
                                .buttonStyle(.bordered)
                        }
                        .padding(.leading, 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .hCentered()
                    }
                    else {
                        KindResolver(nrPost: firstQuote, fullWidth: fullWidth, hideFooter: hideFooter, missingReplyTo: true, isReply: isReply, isDetail:isDetail, connect: connect, grouped: grouped)
                    }
                }
                else if let firstQuoteId = nrPost.firstQuoteId {
                    CenteredProgressView()
                        .frame(height: 250)
                        .onAppear {
                            EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "NoteRow.001")
                            QueuedFetcher.shared.enqueue(id: firstQuoteId)
                        }
                        .onDisappear {
                            QueuedFetcher.shared.dequeue(id: firstQuoteId)
                        }
                }
            }
            else { // IS NOT A REPOST
                KindResolver(nrPost: nrPost, fullWidth: fullWidth, hideFooter: hideFooter, missingReplyTo: missingReplyTo, isReply: isReply, isDetail:isDetail, connect: connect, grouped: grouped)
            }
        }
//        .padding(.vertical, 20)
        // Performance testing
//        .background(Color.random) // NOTEROW BOX BACKGROUND
//        .readSize { size in
//            print("NoteRow size: \(size)")
//        }
//        .background(Color.systemBackground) // NOTEROW BOX BACKGROUND
    }
}

extension View {
  func readSize(onChange: @escaping (CGSize) -> Void) -> some View {
    overlay(
      GeometryReader { geometryProxy in
        Color.clear
          .preference(key: SizePreferenceKey.self, value: geometryProxy.size)
      }
    )
    .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
  }
}

enum ThreadConnectDirection {
    case top
    case bottom
    case both
}

struct NoteRow_Previews: PreviewProvider {
    
    static var previews: some View {
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
            pe.loadReposts()
            pe.loadHighlights()
            pe.loadKind1063()
        }) {
            ScrollView {
                LazyVStack {
                    Group {
                        
//                        if let p = PreviewFetcher.fetchNRPost("1920b9351f01dd92dad21a9eef04781b896cb45260dfc02d9e9c05bda6dfef77") {
//                            // A POST WITH CODE IN QUOTE
//                            PostRowDeletable(nrPost: p, fullWidth: true)
//                                .roundedBoxShadow()
//                                .padding(.horizontal, 0) // FULL WIDTH
//                                .padding(.vertical, 10)
//
//                            PostRowDeletable(nrPost: p)
//                                .roundedBoxShadow()
//                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
//                                .padding(.vertical, 10)
//                        }
//                        if let p = PreviewFetcher.fetchNRPost("347c5332d508c99d57b25dcaad7ee91f4922088b3d9395c447055953d02084e7") {
//                            // A POST WITH CODE
//                            PostRowDeletable(nrPost: p, fullWidth: true)
//                                .roundedBoxShadow()
//                                .padding(.horizontal, 0) // FULL WIDTH
//                                .padding(.vertical, 10)
//
//                            PostRowDeletable(nrPost: p)
//                                .roundedBoxShadow()
//                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
//                                .padding(.vertical, 10)
//                        }
                        if let p = PreviewFetcher.fetchNRPost("115eab2976aee4ca562d83ea6b1d805c6d4e0acf54fe2e6a4e1a62f73c2850cc") {
                            // A POST WITH A @MENTION
//                            PostRowDeletable(nrPost: p, fullWidth: true)
//                                .roundedBoxShadow()
//                                .padding(.horizontal, 0) // FULL WIDTH
//                                .padding(.vertical, 10)
                            
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }
                        
                        
                        if let p = PreviewFetcher.fetchNRPost("576375cd4a87e40f15a7842b43fe4a35651e89a34371b2a41ca79ca7dced1113") {
                            // A POST WITH A YOUTUBE LINK (WITH PREVIEW)
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }
                        
                        if let p = PreviewFetcher.fetchNRPost("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0") {
                            // A POST WITH A @MENTION
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }
                    }
                    Group {
                        if let p = PreviewFetcher.fetchNRPost("dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3") {
                            // A POST WITH WITH JUST TEXt
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }
                        
                        if let p = PreviewFetcher.fetchNRPost("d3b581761bab06fbe727b12b22c33c7b8768d7d9681b45cb6b1f4ad798496e14") {
                            // A POST WITH LINK PREVIEW WITH IMAGE
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }
                        
                        if let p = PreviewFetcher.fetchNRPost("62459426eb9a1aff9bf1a87bba4238614d7b753c914ccd7884dac0aa36e853fe") {
                            // A QUOTE REPOST, USING OLD METHOD (#[5])
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }
                        
                        if let p = PreviewFetcher.fetchNRPost("bf0ca9422b83a35fd3384d4149314bfff9f05e025b5138c9db85d90a41b03ad9") {
                            // A POST WITH 1 GIF
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }
                        
                        if let p = PreviewFetcher.fetchNRPost("6687ee15b74160673449e2bf667d88e246d8101418e167679f2aa10df3bb7c06") {
                            // A POST WITH 1 IMAGE
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }
                        
                        if let p = PreviewFetcher.fetchNRPost("82fcaaa11259aa5f505f1e3a6de06c2b7265179d3d05ef0b74824c4b7ff7eab8") {
                            // A POST WITH 1 IMAGE AND 14 MORE ITEMS
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }
                        
                        if let p = PreviewFetcher.fetchNRPost("5099246907e78edde0169c419543c01dd312fbe2645106c58f476efd65c2f66b") {
                            // A POST WITH A #BITCOIN HASHTAG AND A SINGLE IMAGE
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }
                        
                        
                        if let p = PreviewFetcher.fetchNRPost("9b34fd9a53398fb51493d68ecfd0d64ff922d0cdf5ffd8f0ffab46c9a3cf54e3") {
                            // POST WITH MARKDOWN, EMBEDDED POST/W IMAGE AND 13 MORE ITEMS
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }
                        
                        
                        if let p = PreviewFetcher.fetchNRPost("102177a51af895883e9256b70b2caff6b9ef90230359ee20f6dc7851ec9e5d5a") {
                            // POST WITH A LINKPREVIEW WITHOUT IMAGE META TAG. AND 1 MORE ITEM
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }
                        
                        if let p = PreviewFetcher.fetchNRPost("6701067d37887024cd221c45e77cf3f0e1ef76589006739617ccc8962719a024") {
                            // POST WITH A LINKPREVIEW WITHOUT IMAGE META TAG
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }
                    }
                    Group {
                        if let p = PreviewFetcher.fetchNRPost("da9454d3143de0139cd9e554ed29aa19606657c28dfbc0c12ac12e14db645ab3") {
                            // POST WITH A LINKPREVIEW WITH A VERY WIDE IMAGE
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }
                        
                        if let p = PreviewFetcher.fetchNRPost("59eeb003cf61b329a0c3be1c2d36aae7b6342ec7092d0ee71a4b7d104de8ea10") {
                            // POST WITH A VIDEO
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }


                        if let p = PreviewFetcher.fetchNRPost("cae89d3f54cacf1dfd4ca97077a033350538d1bbdc19dfb571f0b76afe2c9fbc") {
                            // POST WITH A VIDEO
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }

                        
                        if let p = PreviewFetcher.fetchNRPost("71a965d8e8546f8927cea23ad865a429dbec0215f36c5e0edad2323eb00f4851") {
                            // A POST EMBEDDING A NIP-94 IMAGE (FILE META DATA) (KIND 1063) WITH nostr:nevent1...
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }
                        
                        if let p = PreviewFetcher.fetchNRPost("ac0c2960db29828ee4a818337ea56df990d9ddd9278341b96c9fb530b4c4dce8") {
                            // A NIP-94 IMAGE (FILE META DATA) (KIND 1063)
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }

                        
                        if let p = PreviewFetcher.fetchNRPost("68b3330358ab3e554183724bed09cc704e62e9b3e790efbb7e819c81905e71a3") {
                            // A HIGHLIGHT (KIND 9802)
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }
                        
                        if let p = PreviewFetcher.fetchNRPost("2b6996d0695569d97f7dd6fd8f2a32428d4df5ca3f28bfcad6a6cc087ff79e25") {
                            // A POST WITH A NOSTR:NRPFOFILE1 LINK (DOESN'T WORK?) TODO: CHECK THIS
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }
                        
                        if let p = PreviewFetcher.fetchNRPost("f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e") {
                            // A POST WITH JUST 1 LINE OF TEXT
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }
                        
                        if let p = PreviewFetcher.fetchNRPost("7d96834f60c5411be97fe9e4b07e3221c56df531543a11a1d67ff81168033e8e") {
                            // REPOST JUST TEXT
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }
                        
                        if let p = PreviewFetcher.fetchNRPost("fdf989cbe5d26d874a4afaf8a78861fcd3267619e7db467a549a6b33c6dbeeab") {
                            // REPOST POST WITH IMAGE
                            PostRowDeletable(nrPost: p)
                                .roundedBoxShadow()
                                .padding(.horizontal, DIMENSIONS.POST_ROW_HPADDING) // NORMAL
                                .padding(.vertical, 10)
                        }
                    }
                }
                .background(Color("ListBackground"))
                .withSheets()
            }
        }
    }
}
