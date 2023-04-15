//
//  NoteRow.swift
//  Nostur
//
//  Created by Fabian Lachman on 14/03/2023.
//

import SwiftUI

struct NoteRow: View {
    let vPost:VPost
    @ObservedObject var event:Event
    var hideFooter = true // For rendering in NewReply
    var inThread = false // For rendering in thread, hide "Replying to.."
    var connect:ThreadConnectDirection? = nil
    
    private let sp:SocketPool = .shared
    
    init(vPost:VPost, hideFooter:Bool = false, inThread:Bool = false, connect: ThreadConnectDirection? = nil) {
        self.vPost = vPost
        self.event = vPost.event
        self.hideFooter = hideFooter
        self.inThread = inThread
        self.connect = connect
    }
    
    var body: some View {
//        let _ = Self._printChanges()
        if event.deletedById == nil {
            VStack (alignment: .leading) {
                if (event.isRepost) {
                    HStack(spacing:4) {
                        Image(systemName: "arrow.2.squarepath")
                            .fontWeight(.bold)
                            .scaleEffect(0.6)
                        Text("**\(vPost.displayName) reposted**").font(.subheadline)
                            .onTapGesture {
                                UIPasteboard.general.string = event.toNEvent().eventJson()
                            }
                    }
                    .foregroundColor(.gray)
                    .onTapGesture {
                        navigateTo(ContactPath(key: vPost.event.pubkey))
                    }
                    .padding(.leading, 40)
                }
                
                if event.isRepost {
                    // IS REPOST BUT NEED TO FETCH THE REPOSTED POST
                    if (event.firstQuoteId != nil && event.firstQuote == nil) {
                        CenteredProgressView().onAppear {
                            // fetch repost
                            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: event.firstQuoteId!)))
                        }
                    }
                    else {
                        if vPost.event.content == "#[0]" {
                            if let firstQuoteId = event.firstQuoteId {
                                Kind1ById(id: firstQuoteId, hideFooter: false)
                            }
                            else {
                                Kind1(vPost: vPost, hideFooter: true)
                            }
                        }
                        else {
                            Kind1(vPost: vPost, hideFooter: true)
                        }
                    }
                }
                // IS NOT A REPOST
                else {
                    Kind1(vPost: vPost, hideFooter: hideFooter, inThread:inThread, connect:connect)
                    //                .background(Color.random)
                }
            }
            .padding(.top, 20)
            .onAppear {
                //            guard 1 == 2 else { return } // performance check
                //            print("🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴 MY FACE IS APPEAR")
                // should fetch setMetaData if
                // No Contact
                // Contact updated_at is very old
                // followed contact meta data refresh should be updated at app wake up probably
                if (event.contact == nil || event.contact?.metadata_created_at == 0) {
                    print("🔴🔴 NoteRow.onAppear vPost.vContact == nil so: REQ.0:\(event.pubkey)")
                    sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: event.pubkey))) // TODO: MOVE TO VM
                }
                if (event.isRepost && event.firstQuote != nil && event.firstQuote!.contact != nil) {
                    if (event.firstQuote!.contact!.metadata_created_at == 0) {
                        print("🔴🔴 NoteRow.onAppear firstQuite.vContact == nil so: REQ.0:\(event.firstQuote!.pubkey)")
                        sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: event.firstQuote!.pubkey))) // TODO: MOVE TO VM
                    }
                }
            }
        }
        else {
            Text("_Post deleted by \(vPost.displayName)_")
                .hCentered()
        }
    }
    
    
    struct Kind1: View {
        let vPost:VPost
        let hideFooter:Bool // For rendering in NewReply
        let inThread:Bool // For rendering in thread
        var connect:ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
        @ObservedObject var event:Event
         
        let sp:SocketPool = .shared
        let up:Unpublisher = .shared
        @ObservedObject var settings:SettingsStore = .shared
        
        init(vPost: VPost, hideFooter:Bool = true, inThread:Bool = false, connect:ThreadConnectDirection? = nil) {
            self.vPost = vPost
            self.event = vPost.event
            self.hideFooter = hideFooter
            self.inThread = inThread
            self.connect = connect
        }
        
        let THREAD_LINE_OFFSET = 34.0
        
        var body: some View {
            
            HStack(alignment: .top, spacing:0) {
                PFP(pubkey: event.pubkey, pictureUrl: event.contact?.picture)
                    .frame(width: 50, height: 50)
                    .background(alignment: .top, content: {
                        Color("LightGray")
                            .frame(width: 2, height: 20)
                            .offset(x:0, y: -20)
                            .opacity(connect == .top || connect == .both ? 1 : 0)
                    })
                    .onTapGesture {
                        navigateTo(ContactPath(key: event.pubkey)) // TODO: if vPost.contact navigate with that else by .pubkey
                    }
                    .padding(.horizontal, 10)
//                Circle().frame(width: 50, height: 50)
//                    .padding(.horizontal, 10)
//
                VStack(alignment:.leading, spacing: 0) {// Post container
                    HStack { // name + reply + context menu
                        NoteHeaderView(vPost: vPost)
                            .padding(.bottom, 5)
                        Spacer()
                        //                            EventPrivateNoteToggle(event: event)
                        NoteMenuView(vPost: vPost)
                    }
                    if !inThread {
                        ReplyingToFragmentView(vPost: vPost)
                            .padding(.bottom, 5)
                            .contentShape(Rectangle())
                            .onTapGesture { navigateTo(vPost) }
                    }
                    ContentRenderer(vPost: vPost)
                    if (!hideFooter && settings.rowFooterEnabled) {
//                            .frame(height: 30)
                        FooterFragmentView(vPost: vPost)
                            .padding(.top, 10)
                    }
                }
                .padding(.bottom, 10)
            }
            .background(alignment: .leading) {
                Color("LightGray")
                    .frame(width: 2)
                    .offset(x: THREAD_LINE_OFFSET, y: 18)
                    .opacity(connect == .bottom || connect == .both ? 1 : 0)
            }
            .padding(.trailing, 10)
            
        }
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
        
        
        // TODO: find repost of 97a1a5dab19064061b45937c4e3523782d34608bd13278def9af4d5107ece65c
        // maybe: 7edef20143bb4df0c65dff3993bd9f7c5fb755fe6c8fa72cc847299afe52d8fa
        
//        let event0 = PreviewFetcher.fetchVPost("21a1b8e4083c11eab8f280dc0c0bddf3837949df75662e181ad117bd0bd5fdf3")
        //        let event0 = PreviewFetcher.fetchVPost("24ad21d57d59b03f4f9a8931f8bc4ccca84ed6ab257bf62cb84b0d04e0583118")
        //
        let event1 = PreviewFetcher.fetchVPost("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
        //
        let event2 = PreviewFetcher.fetchVPost("dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3")
        //
        //        let event3 = PreviewFetcher.fetchVPost("d3b581761bab06fbe727b12b22c33c7b8768d7d9681b45cb6b1f4ad798496e14")
        //
        //        let event4 = PreviewFetcher.fetchVPost("62459426eb9a1aff9bf1a87bba4238614d7b753c914ccd7884dac0aa36e853fe")
        //
        //        let event5 = PreviewFetcher.fetchVPost("f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e")
        //
        let event6 = PreviewFetcher.fetchVPost("7d96834f60c5411be97fe9e4b07e3221c56df531543a11a1d67ff81168033e8e")
        
        let event7 = PreviewFetcher.fetchVPost("fdf989cbe5d26d874a4afaf8a78861fcd3267619e7db467a549a6b33c6dbeeab")
        
//        let img0 = PreviewFetcher.fetchVPost("f61016921961dfe93981f12d2eff92b0b7e8b3312c8a1cfdabf191d9536ba2ad")
//        let img1 = PreviewFetcher.fetchVPost("bf0ca9422b83a35fd3384d4149314bfff9f05e025b5138c9db85d90a41b03ad9")
//        let img2 = PreviewFetcher.fetchVPost("6687ee15b74160673449e2bf667d88e246d8101418e167679f2aa10df3bb7c06")
//        let img3 = PreviewFetcher.fetchVPost("82fcaaa11259aa5f505f1e3a6de06c2b7265179d3d05ef0b74824c4b7ff7eab8")
//        let img4 = PreviewFetcher.fetchVPost("5099246907e78edde0169c419543c01dd312fbe2645106c58f476efd65c2f66b")
        
//        let eventLong = PreviewFetcher.fetchVPost("9b34fd9a53398fb51493d68ecfd0d64ff922d0cdf5ffd8f0ffab46c9a3cf54e3")
//
        List {
            
            //            Group {
            //                if (img0 != nil) {
            //                    NoteRow(vPost: img0!)
            //                        .listRowInsets(EdgeInsets())
            //                }
            //
            //                if (img1 != nil) {
            //                    NoteRow(vPost: img1!)
            //                        .listRowInsets(EdgeInsets())
            //                }
            //
            //                if (img2 != nil) {
            //                    NoteRow(vPost: img2!)
            //                        .listRowInsets(EdgeInsets())
            //                }
            //
            //                if (img3 != nil) {
            //                    NoteRow(vPost: img3!)
            //                        .listRowInsets(EdgeInsets())
            //                }
            //
            //                if (img4 != nil) {
            //                    NoteRow(vPost: img4!)
            //                        .listRowInsets(EdgeInsets())
            //                }
            
            
            //                if (event0 != nil) {
            //                    NoteRow(vPost: event0!)
            //                        .listRowInsets(EdgeInsets())
            //                }
            //
            Group {
//                if let vPost = PreviewFetcher.fetchVPost("102177a51af895883e9256b70b2caff6b9ef90230359ee20f6dc7851ec9e5d5a") {
//                    NoteRow(vPost: vPost)
//                }
//                if let vPost = PreviewFetcher.fetchVPost("6701067d37887024cd221c45e77cf3f0e1ef76589006739617ccc8962719a024") {
//                    NoteRow(vPost: vPost)
//                }
                
                
//                if (eventLong != nil) {
//                    NoteRow(vPost: eventLong!)
//                }
                
                if (event1 != nil) {
                    NoteRow(vPost: event1!)
                }
                ////
                if (event2 != nil) {
                    NoteRow(vPost: event2!)
                }
                //
                //            NoteRowView(event: event3!)
                //                .listRowInsets(EdgeInsets())
                //
                // QUOTE? TODO:// WAAROM CRASHED DEZE??
                //            if (event4 != nil) {
                //                NoteRowView(event: event4!)
                //                    .listRowInsets(EdgeInsets())
                //            }
                
                //            NoteRowView(event: event5!)
                //                .listRowInsets(EdgeInsets())
                
                if (event6 != nil) {
                    // REPOST, LOADING?
                    NoteRow(vPost: event6!)
                }
                
                if (event7 != nil) {
                    // REPOST
                    NoteRow(vPost: event7!)
                }
                //            }
                //            .frame(maxHeight: 400)
                
            }
            .listRowInsets(EdgeInsets())
            
        }
        .listStyle(.plain)
        .withPreviewEnvironment()
    }
}
