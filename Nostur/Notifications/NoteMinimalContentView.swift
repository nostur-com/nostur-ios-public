//
//  NoteMinimalContentView.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/02/2023.
//

import SwiftUI

struct NoteMinimalContentView: View {
    
    @Environment(\.managedObjectContext) var viewContext
    private let sp:SocketPool = .shared
    let vPost:VPost
    @ObservedObject var event:Event
    let lineLimit:Int
    
    init(vPost:VPost, hideFooter:Bool = false, lineLimit:Int = 0) {
        self.vPost = vPost
        self.event = vPost.event
        self.lineLimit = lineLimit
    }
    
    @Namespace var invoice
    @Namespace var text
    
    var body: some View {
        VStack (alignment: .leading) {
            HStack(alignment: .top) {
                VStack(alignment:.leading, spacing: 3) {
                    MinimalNoteTextRenderView(vPost: vPost, lineLimit: lineLimit)
                    
                    if let quoteVPost = event.firstQuote?.toVPost(plainText: true) {
                        MinimalQuotedNoteFragment(vPost: quoteVPost)
                    }
                    else if (event.firstQuoteId != nil) {
                        CenteredProgressView().onAppear {
                            sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: event.firstQuoteId!)))
                        }
                    }
                }
                .padding(.trailing, 10)
            }
        }
//        .padding(.vertical, 10)
    }
}

struct NoteMinimalContentView_Previews: PreviewProvider {
    
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
        
       
        
        List {
            let event0 = PreviewFetcher.fetchVPost("21a1b8e4083c11eab8f280dc0c0bddf3837949df75662e181ad117bd0bd5fdf3", plainText: true)
    //        let event0 = PreviewFetcher.fetchVPost("24ad21d57d59b03f4f9a8931f8bc4ccca84ed6ab257bf62cb84b0d04e0583118")
    //
            let event1 = PreviewFetcher.fetchVPost("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0", plainText: true)
    //
            let event2 = PreviewFetcher.fetchVPost("dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3", plainText: true)
    //
    //        let event3 = PreviewFetcher.fetchVPost("d3b581761bab06fbe727b12b22c33c7b8768d7d9681b45cb6b1f4ad798496e14")
            
            let event4 = PreviewFetcher.fetchVPost("62459426eb9a1aff9bf1a87bba4238614d7b753c914ccd7884dac0aa36e853fe", plainText: true)
    //
    //        let event5 = PreviewFetcher.fetchVPost("f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e")
    //
            let event6 = PreviewFetcher.fetchVPost("7d96834f60c5411be97fe9e4b07e3221c56df531543a11a1d67ff81168033e8e", plainText: true)

            let event7 = PreviewFetcher.fetchVPost("fdf989cbe5d26d874a4afaf8a78861fcd3267619e7db467a549a6b33c6dbeeab", plainText: true)
            
            Group {
                if (event0 != nil) {
                    NoteMinimalContentView(vPost: event0!)
                        
                }
                
                if (event1 != nil) {
                    NoteMinimalContentView(vPost: event1!)
                        
                }
                //
                if (event2 != nil) {
                    NoteMinimalContentView(vPost: event2!)
                        
                }
                //
                //            NoteMinimalContentView(vPost: event3!)
                //
                //
                // QUOTE?
                if (event4 != nil) {
                    NoteMinimalContentView(vPost: event4!)
                        
                }
                
                //            NoteMinimalContentView(vPost: event5!)
                //                .listRowInsets(EdgeInsets())
                
                if (event6 != nil) {
                    // REPOST, LOADING?
                    NoteMinimalContentView(vPost: event6!)
                }
                
                if (event7 != nil) {
                    // REPOST
                    NoteMinimalContentView(vPost: event7!)
                }
            }
            .listRowInsets(EdgeInsets())
            
        }
        .withPreviewEnvironment()
    }
}
