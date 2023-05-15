//
//  ArticleFormatting.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/03/2023.
//

import SwiftUI
import Nuke
import NukeUI
import Combine

// Renders embeds (VIEWS), not links (in TEXT)
struct ContentRenderer: View { // VIEW things
    let nrPost:NRPost
    let isDetail:Bool
    let fullWidth:Bool
    let availableWidth:CGFloat
//    @ObservedObject var event:Event
    @State var renderedElements:[ContentElement]
//    @State var subscriptions = Set<AnyCancellable>()
    
    init(nrPost: NRPost, isDetail:Bool = false, fullWidth:Bool = false, availableWidth:CGFloat) {
        self.isDetail = isDetail
        self.nrPost = nrPost
//        self.event = nrPost.event
        self.fullWidth = fullWidth
        self.availableWidth = availableWidth
        _renderedElements = State(initialValue: isDetail ? nrPost.contentElementsDetail : nrPost.contentElements )
    }
    
    @State var f:FullScreenItem?
    @State private var viewSize: CGSize = .zero
    
    var body: some View {
        VStack(alignment:.leading, spacing:0) {
            ForEach(renderedElements.indices, id:\.self) { index in
                switch renderedElements[index] {
                        //                    case .plain(let text):
                        //                        Text(text)
                        //                            .textSelection(.enabled)
                        //                            .multilineTextAlignment(.leading)
                        //                            .accentColor(Color("AccentColor"))
                        //                            .tint(Color("AccentColor"))
                        //                            .lineSpacing(3)
                    case .nevent1(let identifier):
                        NEventView(identifier: identifier)
                    case .nprofile1(let identifier):
                        NProfileView(identifier: identifier)
                    case .note1(let noteId):
                        if let noteHex = hex(noteId) {
                            QuoteById(id: noteHex)
                                .padding(.vertical, 5)
                                .padding(.horizontal, fullWidth ? 10 : 0)
                        }
                        else {
                            let _ = print("🔴🔴🔴🔴 Problem converting \(noteId) to hex")
                            EmptyView()
                        }
                        //                            .frame(maxWidth: .infinity, maxHeight:400, alignment: .leading)
                    case .noteHex(let hex):
                        QuoteById(id: hex)
                            .padding(.vertical, 5)
                            .padding(.horizontal, fullWidth ? 10 : 0)
                        //                            .frame(maxWidth: .infinity, maxHeight:400, alignment: .leading)
                    case .text(let attributedStringWithPs, let oringalText):
                        // BROKEN SHIT
                        //                            Text(string)
                        //                            .fixedSize(horizontal: false, vertical: true)
                        //                            .overlay(MarkdownText(string))
                        NRContentTextRenderer(attributedStringWithPs: attributedStringWithPs, originalText: oringalText)
                        //                            .padding(0)
                        //                            .frame(maxWidth: .infinity)
                        //                            .padding(.vertical, 5)
                        //                                                    .frame(maxWidth: .infinity, alignment: .leading)
                    case .lnbc(let text):
                        LightningInvoice(invoice: text)
                            .padding(.horizontal, fullWidth ? 10 : 0)
                    case .video(let url):
                    SingleVideoViewer(url: url, pubkey: nrPost.pubkey, videoWidth: availableWidth, isFollowing:nrPost.contact?.following ?? false)
                            .padding(.vertical, 5)
                    case .image(let url):
                    SingleMediaViewer(url: url, pubkey: nrPost.pubkey, imageWidth: availableWidth, isFollowing: nrPost.contact?.following ?? false, fullWidth: fullWidth)
                            .padding(.vertical, 5)
                    case .linkPreview(let url):
                        // TODO: do no link preview if restrictAutoDownload...
                        LinkPreviewView(url: url)
                            .padding(.horizontal, fullWidth ? 10 : 0)
                            .padding(.vertical, 5)
                    case .postPreviewImage(let uiImage):
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 600)
                            .padding(.top, 10)
                    default:
                        EmptyView()
                }
            }
        }
        //        .frame(maxWidth: .infinity, maxHeight:450, alignment: .leading)
        .onAppear {
            // TODO FIX ME....
//            guard !nrPost.event.isPreview else { return }
//            event.objectWillChange
//                .sink {
//                    
////                    let followingKeys = NosturState.shared.followingPublicKeys
//                    let context = DataProvider.shared().bg
//                    context.perform {
//                        let transformer = VPostTransformer.bg
//                     
//                        guard let privateEvent = context.object(with: event.objectID) as? Event else { return }
//                        let renderedElements = transformer.renderElements(privateEvent).0
//                        
//                        let firstQuote = renderedElements.first(where: { element in
//                            if case .note1 = element {
//                                return true
//                            }
//                            return false
//                        })
//                        
//                        var renderedForRow:[MarkdownElement] {
//                            var gotVideo = false
//                            return renderedElements
//                                .filter { element in
//                                    if case .video = element {
//                                        if (!gotVideo) {
//                                            gotVideo = true
//                                            return true
//                                        }
//                                        return false
//                                    }
//                                    if case .note1 = element {
//                                        return element == firstQuote
//                                    }
//                                    else {
//                                        return true
//                                    }
//                                }
//                        }
//                                                
//                        DispatchQueue.main.async {
//                            self.renderedElements = isDetail ? renderedElements : renderedForRow
//                        }
//                    }
////                    DataProvider.shared().container.performBackgroundTask { context in
////
////                    }
//    
//                }
//                .store(in: &subscriptions)
        }
    }
}

struct RowContentRenderer_Previews: PreviewProvider {
    
    static var previews: some View {
        
        ScrollView {
            VStack {
                if let nrPost = PreviewFetcher.fetchNRPost("9b34fd9a53398fb51493d68ecfd0d64ff922d0cdf5ffd8f0ffab46c9a3cf54e3") {
                    ContentRenderer(nrPost: nrPost, availableWidth: UIScreen.main.bounds.width)
                }
                if let nrPost = PreviewFetcher.fetchNRPost("102177a51af895883e9256b70b2caff6b9ef90230359ee20f6dc7851ec9e5d5a") {
                    ContentRenderer(nrPost: nrPost, availableWidth: UIScreen.main.bounds.width)
                }
            }
        }
        .withPreviewEnvironment()
    }
}

struct QuoteById: View {
    
    let id:String
    
    @FetchRequest
    var events:FetchedResults<Event>
    
    @State var nrPost:NRPost?
    
    init(id:String) {
        self.id = id
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "id == %@", id)
        fr.fetchLimit = 1
        _events = FetchRequest(fetchRequest: fr)
    }
    
    var body: some View {
        VStack {
            if let event = events.first {
                if let nrPost = nrPost {
                    QuotedNoteFragmentView(nrPost: nrPost)
                }
                else {
                    Color.clear
                        .frame(height: 150)
                        .task {
    //                        let followingKeys = NosturState.shared.followingPublicKeys
    //                        DataProvider.shared().container.performBackgroundTask { context in
                            DataProvider.shared().bg.perform {
    //                            let transformer = VPostTransformer.bg
                                if let eventBG = event.toBG() {
                                    let nrPost = NRPost(event: eventBG)
                                    
                                    DispatchQueue.main.async {
                                        self.nrPost = nrPost
                                    }
                                }
                            }
                        }
                }
            }
            else {
                ProgressView()
                    .hCentered()
                    .onAppear {
                        print("🟢 Fetching for QuotedNoteFragmentView \(id)")
                        SocketPool.shared.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEventAndReferences(id: id)))
                    }
            }
        }
    }
}

struct Kind1ById: View {
    
    let id:String
    let hideFooter:Bool
    let fullWidth:Bool
    //    @ObservedObject var vm:EventVM // no vm want fr is not updating after receiving from websocket
    
    @FetchRequest
    var events:FetchedResults<Event>
    //
    init(id:String, hideFooter:Bool = true, fullWidth:Bool = false) {
        self.id = id
        self.hideFooter = hideFooter
        self.fullWidth = fullWidth
        let fr = Event.fetchRequest()
        fr.predicate = NSPredicate(format: "id == %@", id)
        fr.fetchLimit = 1
        _events = FetchRequest(fetchRequest: fr)
    }
    
    var body: some View {
        if let firstEvent = events.first {
            let nrPost = NRPost(event: firstEvent) // TODO: ????
            let _ = print("☠️☠️☠️☠️ NRPost() Kind1ById")
            if fullWidth {
                Kind1(nrPost: nrPost, hideFooter:hideFooter)
            }
            else {
                Kind1Default(nrPost: nrPost, hideFooter:hideFooter)
            }
        }
        else {
            ProgressView()
                .hCentered()
                .onAppear {
                    print("🟢 Fetching for Kind1ById \(id)")
                    SocketPool.shared.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: id)))
                    //                    SocketPool.shared.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEventAndReferences(id: id)))
                }
        }
    }
}

