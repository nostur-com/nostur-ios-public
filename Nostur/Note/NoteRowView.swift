//
//  MessageView.swift
//  Nostur
//
//  Created by Fabian Lachman on 05/01/2023.
//

import SwiftUI
import CoreData
import LightningDevKit

struct NoteRowView: View {
    
    @Environment(\.managedObjectContext) var viewContext
    private let sp:SocketPool = .shared
    private let nav:NavigationModel = .shared
    var event:Event
//    @ObservedObject var event:Event

    var hideFooter = false // For rendering in NewReply
    
//    @State private var backgroundColor = Color.green
    
    enum type {
        case note
        case lightningInvoice
    }
    
    let type:NoteRowView.type
    
    init(event: Event, hideFooter:Bool = false) {
//        print("🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴 MY FACE IS INIT")
        self.event = event
        self.hideFooter = hideFooter
                
        if event.noteText.prefix(4).lowercased() == "lnbc" && Invoice.fromStr(s: event.noteText).getValue() != nil {
            self.type = .lightningInvoice
        }
        else {
            self.type = .note
        }
        
    }
    
    @AppStorage("devToggle") var devToggle: Bool = true
    @State private var isVisible = false
    
    @Namespace var invoice
    @Namespace var text
    
    var body: some View {
        let _ = Self._printChanges()
        VStack (alignment: .leading) {
            if (event.isRepost) {
                HStack {
                    Image(systemName: "arrow.2.squarepath")
                    Text("\(event.name) reposted")
                    if (devToggle) {
                        Text("id: \(String(event.id!.prefix(5)))")
                            .onTapGesture {
                                UIPasteboard.general.string = event.id!
                            }
                    }
                }
                .foregroundColor(.gray)
                .onTapGesture {
                    nav.navigateTo(ContactPath(key: event.pubkey!))
                }
                .padding(.leading, 45)
            }
            
            // IS REPOST AND ALL DATA IS HERE
            if (event.isRepost && event.firstQuoteId != nil && event.firstQuote != nil) {
                HStack(alignment: .top) {
                        VStack {
                            ProfilePic(event: event.firstQuote!)
                                .padding(.horizontal, 10)
                                .onTapGesture {
                                    nav.navigateTo(ContactPath(key: event.firstQuote!.pubkey!))
                                }
                        }
                        
                        VStack(alignment:.leading, spacing: 3) {// Tweet container
                            HStack { // name + reply + context menu
                                NoteHeader(event:event.firstQuote!)
                                Spacer()
                                NoteMenu(event: event.firstQuote!)//.opacity(0)
                            }
                            ReplyingToFragment(event: event.firstQuote!)
                            
                            switch self.type {
                                case .lightningInvoice:
                                    LightningInvoice(invoice: event.firstQuote!.noteText)
                                        .id(invoice)
                                default:
                                    NoteTextRenderView(event:event.firstQuote!, useLinelimit: true)
                                        .id(text)
                                        .onTapGesture { nav.navigateTo(event.firstQuote!) }
                            }
                            
                            
                            if (event.firstQuote!.firstQuoteId != nil && event.firstQuote!.firstQuote != nil) {
                                QuotedNoteFragment(event: event.firstQuote!.firstQuote!)
                            }
                            else if (event.firstQuote!.firstQuote != nil) {
                                ProgressView().onAppear {
                                    sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: event.firstQuote!.firstQuoteId!)))
                                }
                            }
                            
                            if (1 == 1 && !hideFooter) {
                                FooterFragment(event: event.firstQuote!)//.border(.red)
                            }
                            
                        }
                        .padding(.trailing, 10)
                        //                        .padding(.bottom, 5)
                    }
            }
            // IS REPOST BUT NEED TO FETCH THE REPOSTED POST
            else if (event.isRepost && event.firstQuoteId != nil && event.firstQuote == nil) {
                ProgressView().onAppear {
                    // fetch repost
                    let mentionTag = TagsHelpers(event.tags()).mentionEtags()?.first
                    if mentionTag != nil {
                        sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: mentionTag!.id)))
                    }
                }
            }
            // IS NOT A REPOST
            else {
                HStack(alignment: .top) {
                        VStack {
                            ProfilePic(event: event)
                                .padding(.horizontal, 10)
                                .onTapGesture {
                                    nav.navigateTo(ContactPath(key: event.pubkey!))
                                }
                        }
                        
                        VStack(alignment:.leading, spacing: 3) {// Tweet container
                            HStack { // name + reply + context menu
                                NoteHeader(event:event)
                                Spacer()
                                NoteMenu(event: event)//.opacity(0)
                            }
                            ReplyingToFragment(event: event)
                            
                            switch self.type {
                                case .lightningInvoice:
                                    LightningInvoice(invoice: event.noteText)
//                                        .onAppear {
//                                            withAnimation(.easeInOut(duration: 2.0)) {
//                                                backgroundColor = Color(uiColor: .systemBackground)
//                                            }
//                                        }
                                default:
                                    NoteTextRenderView(event:event, useLinelimit: true)
                                        .onTapGesture { nav.navigateTo(event) }
//                                        .onAppear {
//                                            withAnimation(.easeInOut(duration: 2.0)) {
//                                                backgroundColor = Color(uiColor: .systemBackground)
//                                            }
//                                        }
                            }
                            
                            
                            if (event.firstQuoteId != nil && event.firstQuote != nil) {
                                QuotedNoteFragment(event: event.firstQuote!)
                            }
                            else if (event.firstQuote != nil) {
                                ProgressView().onAppear {
                                    sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: event.firstQuoteId!)))
                                }
                            }
                            
                            if (1 == 1 && !hideFooter) {
                                FooterFragment(event: event)//.border(.red)
                            }
                            
                        }
                        .padding(.trailing, 10)
                        //                        .padding(.bottom, 5)
                    }
            }
        }
        .background(
            Color(.systemBackground)
                .onTapGesture {
                    nav.navigateTo(event.isRepost && event.firstQuote != nil ? event.firstQuote! : event)
//                    if (eventOrRepost != nil) {
//                        nav.navigateTo(eventOrRepost)
//                    }
//                    else {
//                        nav.navigateTo(NotePath(id: event.firstQuoteId!))
//                    }
                }
        )
        .onAppear {
//            guard 1 == 2 else { return } // performance check
//            print("🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴 MY FACE IS APPEAR")
            // should fetch setMetaData if
            // No Contact
            // Contact updated_at is very old
            // followed contact meta data refresh should be updated at app wake up probably
            if (event.contact == nil || event.contact?.updated_at == 0) {
                print("🔴🔴 NoteRow.onAppear event.contact == nil so: REQ.0:\(event.pubkey!)")
                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: event.pubkey!)))
            }
            if (event.isRepost && event.firstQuote != nil && event.firstQuote!.contact != nil) {
                if (event.firstQuote!.contact!.updated_at == 0) {
                    print("🔴🔴 NoteRow.onAppear event.firstQuite.contact == nil so: REQ.0:\(event.pubkey!)")
                    sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: event.firstQuote!.pubkey!)))
                }
            }
        }
        //        .frame(minHeight: 140)//.border(.red)
        .padding(.vertical, 10)
        //        .background(Color.random)
        
    }
}

struct NoteRowView_Previews: PreviewProvider {
    
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
        
        let event0 = PreviewFetcher.fetchEvent("21a1b8e4083c11eab8f280dc0c0bddf3837949df75662e181ad117bd0bd5fdf3")
//        let event0 = PreviewFetcher.fetchEvent("24ad21d57d59b03f4f9a8931f8bc4ccca84ed6ab257bf62cb84b0d04e0583118")
//
        let event1 = PreviewFetcher.fetchEvent("1b2a98e1d653592a93398c0f93a2931b6399c6ec8332700c79cbefbd814eefd0")
//
        let event2 = PreviewFetcher.fetchEvent("dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3")
//
//        let event3 = PreviewFetcher.fetchEvent("d3b581761bab06fbe727b12b22c33c7b8768d7d9681b45cb6b1f4ad798496e14")
        
        let event4 = PreviewFetcher.fetchEvent("62459426eb9a1aff9bf1a87bba4238614d7b753c914ccd7884dac0aa36e853fe")
//
//        let event5 = PreviewFetcher.fetchEvent("f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e")
//
        let event6 = PreviewFetcher.fetchEvent("7d96834f60c5411be97fe9e4b07e3221c56df531543a11a1d67ff81168033e8e")

        let event7 = PreviewFetcher.fetchEvent("fdf989cbe5d26d874a4afaf8a78861fcd3267619e7db467a549a6b33c6dbeeab")
        
        List {
            
            if (event0 != nil) {
                NoteRowView(event: event0!)
                    .listRowInsets(EdgeInsets())
            }

            if (event1 != nil) {
                NoteRowView(event: event1!)
                    .listRowInsets(EdgeInsets())
            }
//
            if (event2 != nil) {
                NoteRowView(event: event2!)
                    .listRowInsets(EdgeInsets())
            }
//
//            NoteRowView(event: event3!)
//                .listRowInsets(EdgeInsets())
//
            // QUOTE?
            if (event4 != nil) {
                NoteRowView(event: event4!)
                    .listRowInsets(EdgeInsets())
            }

//            NoteRowView(event: event5!)
//                .listRowInsets(EdgeInsets())
            
            if (event6 != nil) {
                // REPOST, LOADING?
                NoteRowView(event: event6!)
                    .listRowInsets(EdgeInsets())
            }

            if (event7 != nil) {
                // REPOST
                NoteRowView(event: event7!)
                    .listRowInsets(EdgeInsets())
            }
            
        }
        .listStyle(PlainListStyle())
        .withPreviewEnvironment()
    }
}
