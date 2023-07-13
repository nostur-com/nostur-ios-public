//
//  NoteMinimalContentView.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/02/2023.
//

import SwiftUI

struct NoteMinimalContentView: View {
    
    private let sp:SocketPool = .shared
    @ObservedObject var nrPost:NRPost
    var lineLimit:Int = 0
    
    var body: some View {
        VStack (alignment: .leading) {
            HStack(alignment: .top) {
                VStack(alignment:.leading, spacing: 3) {
                    MinimalNoteTextRenderView(nrPost: nrPost, lineLimit: lineLimit)
                    
                    if let quoteNRPost = nrPost.firstQuote {
                        MinimalQuotedNoteFragment(nrPost: quoteNRPost)
                    }
                    else if let firstQuoteId = nrPost.firstQuoteId {
                        CenteredProgressView().onAppear {
                            req(RM.getEvent(id: firstQuoteId))
                        }
                    }
                }
                .padding(.trailing, 10)
            }
        }
    }
}

struct NoteMinimalContentView_Previews: PreviewProvider {
    
    static var previews: some View {
        
        // #[2]
        // 115eab2976aee4ca562d83ea6b1d805c6d4e0acf54fe2e6a4e1a62f73c2850cc
        
        // #[0]
        // 1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0
        
        // with youtube preview
        // id: 576375cd4a87e40f15a7842b43fe4a35651e89a34371b2a41ca79ca7dced1113
        
        // reply to unfetched contact
        // dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3
        
        // reply to known  contact
        // f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e
        
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
        }) {
            List {
                let event0 = PreviewFetcher.fetchNRPost("21a1b8e4083c11eab8f280dc0c0bddf3837949df75662e181ad117bd0bd5fdf3")
        //        let event0 = PreviewFetcher.fetchNRPost("24ad21d57d59b03f4f9a8931f8bc4ccca84ed6ab257bf62cb84b0d04e0583118")
        //
                let event1 = PreviewFetcher.fetchNRPost("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
        //
                let event2 = PreviewFetcher.fetchNRPost("dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3")
        //
        //        let event3 = PreviewFetcher.fetchNRPost("d3b581761bab06fbe727b12b22c33c7b8768d7d9681b45cb6b1f4ad798496e14")
                
                let event4 = PreviewFetcher.fetchNRPost("62459426eb9a1aff9bf1a87bba4238614d7b753c914ccd7884dac0aa36e853fe")
        //
        //        let event5 = PreviewFetcher.fetchNRPost("f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e")
        //
                let event6 = PreviewFetcher.fetchNRPost("7d96834f60c5411be97fe9e4b07e3221c56df531543a11a1d67ff81168033e8e")

                let event7 = PreviewFetcher.fetchNRPost("fdf989cbe5d26d874a4afaf8a78861fcd3267619e7db467a549a6b33c6dbeeab")
                
                Group {
                    if (event0 != nil) {
                        NoteMinimalContentView(nrPost: event0!)
                            
                    }
                    
                    if (event1 != nil) {
                        NoteMinimalContentView(nrPost: event1!)
                            
                    }
                    //
                    if (event2 != nil) {
                        NoteMinimalContentView(nrPost: event2!)
                            
                    }
                    //
                    //            NoteMinimalContentView(nrPost: event3!)
                    //
                    //
                    // QUOTE?
                    if (event4 != nil) {
                        NoteMinimalContentView(nrPost: event4!)
                            
                    }
                    
                    //            NoteMinimalContentView(nrPost: event5!)
                    //                .listRowInsets(EdgeInsets())
                    
                    if (event6 != nil) {
                        // REPOST, LOADING?
                        NoteMinimalContentView(nrPost: event6!)
                    }
                    
                    if (event7 != nil) {
                        // REPOST
                        NoteMinimalContentView(nrPost: event7!)
                    }
                }
                .listRowInsets(EdgeInsets())
                
            }
        }
    }
}
