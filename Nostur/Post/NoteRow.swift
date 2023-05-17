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
    var inThread = false // For rendering in thread, hide "Replying to.."
    var connect:ThreadConnectDirection? = nil
    let fullWidth:Bool
    let isReply:Bool // is reply on PostDetail (needs 2*10 less box width)
    let isDetail:Bool
    
    private let sp:SocketPool = .shared
    
    init(nrPost:NRPost, hideFooter:Bool = false, inThread:Bool = false, connect: ThreadConnectDirection? = nil, fullWidth:Bool = false, isReply:Bool = false, isDetail:Bool = false) {
        self.nrPost = nrPost
        self.hideFooter = hideFooter
        self.inThread = inThread
        self.connect = connect
        self.fullWidth = fullWidth
        self.isReply = isReply
        self.isDetail = isDetail
    }
    
    var body: some View {
//        let _ = Self._printChanges()
        VStack (alignment: .leading) {
            if (nrPost.isRepost) {
                HStack(spacing:4) {
                    Image(systemName: "arrow.2.squarepath")
                        .fontWeight(.bold)
                        .scaleEffect(0.6)
                    Text("**\(nrPost.contact?.anyDisplayName ?? "...") reposted**").font(.subheadline)
                        .onTapGesture {
                            UIPasteboard.general.string = nrPost.mainEvent.toNEvent().eventJson()
                        }
                }
                .foregroundColor(.gray)
                .onTapGesture {
                    navigateTo(ContactPath(key: nrPost.pubkey))
                }
                .padding(.leading, 40)
            }
            
            if nrPost.isRepost, let firstQuote = nrPost.firstQuote {
                // CASE - WE HAVE IT IN VPOST
                KindResolver(nrPost: firstQuote, inThread: inThread, connect: connect)
            }
            // CASE - We need to fetch it
            else if nrPost.isRepost, let firstQuoteId = nrPost.firstQuoteId {
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
            else { // IS NOT A REPOST
                KindResolver(nrPost: nrPost, fullWidth: fullWidth, hideFooter: hideFooter, inThread: inThread, isReply: isReply, isDetail:isDetail, connect: connect)
            }
        }
        .padding(.top, 20)
//            .background(Color.random) // NOTEROW BOX BACKGROUND
        .background(Color.systemBackground) // NOTEROW BOX BACKGROUND
    }
}

enum ThreadConnectDirection {
    case top
    case bottom
    case both
}

struct NoteRow_Previews: PreviewProvider {
    
    static var previews: some View {
        
        // #[2]
        // 115eab2976aee4ca562d83ea6b1d805c6d4e0acf54fe2e6a4e1a62f73c2850cc
        
        // #[0]
        // 1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0
        
        // note.id 6f74b952991bb12b61de7c5891706711e51c9e34e9f120498d32226f3c1f4c81
        // pubkey: 5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0
        
        // with youtube preview
        // id: 576375cd4a87e40f15a7842b43fe4a35651e89a34371b2a41ca79ca7dced1113
        
        // reply to unfetched contact
        // dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3
        
        // reply to known  contact
        // f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e
        
//        let event0 = PreviewFetcher.fetchNRPost("21a1b8e4083c11eab8f280dc0c0bddf3837949df75662e181ad117bd0bd5fdf3")
        //        let event0 = PreviewFetcher.fetchNRPost("24ad21d57d59b03f4f9a8931f8bc4ccca84ed6ab257bf62cb84b0d04e0583118")
        //
        let event1 = PreviewFetcher.fetchNRPost("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
        //
        let event2 = PreviewFetcher.fetchNRPost("dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3")
        //
        //        let event3 = PreviewFetcher.fetchNRPost("d3b581761bab06fbe727b12b22c33c7b8768d7d9681b45cb6b1f4ad798496e14")
        //
        //        let event4 = PreviewFetcher.fetchNRPost("62459426eb9a1aff9bf1a87bba4238614d7b753c914ccd7884dac0aa36e853fe")
        //
        //        let event5 = PreviewFetcher.fetchNRPost("f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e")
        //
        let event6 = PreviewFetcher.fetchNRPost("7d96834f60c5411be97fe9e4b07e3221c56df531543a11a1d67ff81168033e8e")
        
        let event7 = PreviewFetcher.fetchNRPost("fdf989cbe5d26d874a4afaf8a78861fcd3267619e7db467a549a6b33c6dbeeab")
        
//        let img0 = PreviewFetcher.fetchNRPost("f61016921961dfe93981f12d2eff92b0b7e8b3312c8a1cfdabf191d9536ba2ad")
//        let img1 = PreviewFetcher.fetchNRPost("bf0ca9422b83a35fd3384d4149314bfff9f05e025b5138c9db85d90a41b03ad9")
//        let img2 = PreviewFetcher.fetchNRPost("6687ee15b74160673449e2bf667d88e246d8101418e167679f2aa10df3bb7c06")
//        let img3 = PreviewFetcher.fetchNRPost("82fcaaa11259aa5f505f1e3a6de06c2b7265179d3d05ef0b74824c4b7ff7eab8")
//        let img4 = PreviewFetcher.fetchNRPost("5099246907e78edde0169c419543c01dd312fbe2645106c58f476efd65c2f66b")
        
//        let eventLong = PreviewFetcher.fetchNRPost("9b34fd9a53398fb51493d68ecfd0d64ff922d0cdf5ffd8f0ffab46c9a3cf54e3")
//
        ScrollView {
            LazyVStack {
                
                //            Group {
                //                if (img0 != nil) {
                //                    PostRowDeletable(nrPost: img0!)
                //                        .listRowInsets(EdgeInsets())
                //                }
                //
                //                if (img1 != nil) {
                //                    PostRowDeletable(nrPost: img1!)
                //                        .listRowInsets(EdgeInsets())
                //                }
                //
                //                if (img2 != nil) {
                //                    PostRowDeletable(nrPost: img2!)
                //                        .listRowInsets(EdgeInsets())
                //                }
                //
                //                if (img3 != nil) {
                //                    PostRowDeletable(nrPost: img3!)
                //                        .listRowInsets(EdgeInsets())
                //                }
                //
                //                if (img4 != nil) {
                //                    PostRowDeletable(nrPost: img4!)
                //                        .listRowInsets(EdgeInsets())
                //                }
                
                
                //                if (event0 != nil) {
                //                    PostRowDeletable(nrPost: event0!)
                //                        .listRowInsets(EdgeInsets())
                //                }
                //
                Group {
                    //                if let nrPost = PreviewFetcher.fetchNRPost("102177a51af895883e9256b70b2caff6b9ef90230359ee20f6dc7851ec9e5d5a") {
                    //                    PostRowDeletable(nrPost: nrPost)
                    //                }
                    //                if let nrPost = PreviewFetcher.fetchNRPost("6701067d37887024cd221c45e77cf3f0e1ef76589006739617ccc8962719a024") {
                    //                    PostRowDeletable(nrPost: nrPost)
                    //                }
                    
                    
                    //                if (eventLong != nil) {
                    //                    PostRowDeletable(nrPost: eventLong!)
                    //                }
                    
                    if let kind1063quoted = PreviewFetcher.fetchNRPost("71a965d8e8546f8927cea23ad865a429dbec0215f36c5e0edad2323eb00f4851") {
                        PostRowDeletable(nrPost: kind1063quoted)
                    }
                    
                    if let kind1063 = PreviewFetcher.fetchNRPost("ac0c2960db29828ee4a818337ea56df990d9ddd9278341b96c9fb530b4c4dce8") {
                        PostRowDeletable(nrPost: kind1063)
                    }
                    
                    if let highlight = PreviewFetcher.fetchNRPost("68b3330358ab3e554183724bed09cc704e62e9b3e790efbb7e819c81905e71a3") {
                        PostRowDeletable(nrPost: highlight)
                    }
                    
                    if let nrPost = PreviewFetcher.fetchNRPost("2b6996d0695569d97f7dd6fd8f2a32428d4df5ca3f28bfcad6a6cc087ff79e25") {
                        PostRowDeletable(nrPost: nrPost)
                    }
                    
                    if (event1 != nil) {
                        PostRowDeletable(nrPost: event1!)
                    }
                    ////
                    if (event2 != nil) {
                        PostRowDeletable(nrPost: event2!)
                    }
                    //
                    //            NoteRowView(event: event3!)
                    //                .listRowInsets(EdgeInsets())
                    //
                    
                    //            NoteRowView(event: event5!)
                    //                .listRowInsets(EdgeInsets())
                    
                    if (event6 != nil) {
                        // REPOST, LOADING?
                        PostRowDeletable(nrPost: event6!)
                    }
                    
                    if (event7 != nil) {
                        // REPOST
                        PostRowDeletable(nrPost: event7!)
                    }
                    //            }
                    //            .frame(maxHeight: 400)
                    
                }
                .listRowInsets(EdgeInsets())
                
            }
        }
        .withPreviewEnvironment()
    }
}
