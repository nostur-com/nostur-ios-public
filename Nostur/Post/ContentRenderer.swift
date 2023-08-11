//
//  ContentRenderer.swift
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
    @ObservedObject var nrPost:NRPost
    let isDetail:Bool
    let fullWidth:Bool
    let availableWidth:CGFloat
    let contentElements:[ContentElement]
    
    init(nrPost: NRPost, isDetail:Bool = false, fullWidth:Bool = false, availableWidth:CGFloat) {
        self.isDetail = isDetail
        self.nrPost = nrPost
        self.fullWidth = fullWidth
        self.availableWidth = availableWidth
        self.contentElements = isDetail ? nrPost.contentElementsDetail : nrPost.contentElements
    }
    
//    @State var f:FullScreenItem?
    @State private var viewSize: CGSize = .zero
    
    var body: some View {
        VStack(alignment:.leading, spacing:0) {
            ForEach(contentElements) { contentElement in
                switch contentElement {
                case .nevent1(let identifier):
                    NEventView(identifier: identifier)
                        .padding(.vertical, 10)
                case .npub1(let npub):
                    if let pubkey = hex(npub) {
                        ProfileCardByPubkey(pubkey: pubkey)
                            .padding(.vertical, 10)
//                            .padding(.horizontal, fullWidth ? 10 : 0)
                    }
                case .nprofile1(let identifier):
                    NProfileView(identifier: identifier)
                case .note1(let noteId):
                    if let noteHex = hex(noteId) {
                        QuoteById(id: noteHex)
                            .padding(.vertical, 10)
//                            .padding(.horizontal, fullWidth ? 10 : 0)
                    }
                    else {
                        let _ = L.og.error("🔴🔴🔴🔴 Problem converting \(noteId) to hex")
                        EmptyView()
                    }
                case .noteHex(let hex):
                    QuoteById(id: hex)
                        .padding(.vertical, 10)
//                        .padding(.horizontal, fullWidth ? 10 : 0)
                case .code(let code): // For text notes
                    Text(verbatim: code)
                        .font(.system(.body, design: .monospaced))
//                        .padding(.horizontal, fullWidth ? 10 : 0)
                        .onTapGesture {
                            guard !isDetail else { return }
                            navigateTo(nrPost)
                        }
                case .text(let attributedStringWithPs): // For text notes
                    NRContentTextRenderer(attributedStringWithPs: attributedStringWithPs)
//                        .padding(.horizontal, fullWidth ? 10 : 0)
                        .onTapGesture {
                            guard !isDetail else { return }
                            navigateTo(nrPost)
                        }
                case .md(let markdownContentWithPs): // For long form articles
                    NRContentMarkdownRenderer(markdownContentWithPs: markdownContentWithPs)
//                        .padding(.horizontal, fullWidth ? 20 : 0)
                        .onTapGesture {
                            guard !isDetail else { return }
                            navigateTo(nrPost)
                        }
                case .lnbc(let text):
                    LightningInvoice(invoice: text, nrPost:nrPost)
                        .padding(.vertical, 10)
//                        .padding(.horizontal, fullWidth ? 10 : 0)
                case .video(let url):
                    NosturVideoViewur(url: url, pubkey: nrPost.pubkey, videoWidth: availableWidth, isFollowing:nrPost.following, contentPadding: nrPost.kind == 30023 ? 20 : 10)
                        .padding(.vertical, 10)
                case .image(let url):
                    SingleMediaViewer(url: url, pubkey: nrPost.pubkey, imageWidth: availableWidth, isFollowing: nrPost.following, fullWidth: fullWidth, forceShow: nrPost.following, contentPadding: nrPost.kind == 30023 ? 20 : 10)
                        .padding(.vertical, 10)
                case .linkPreview(let url):
                    // TODO: do no link preview if restrictAutoDownload...
                    LinkPreviewView(url: url)
//                        .padding(.horizontal, fullWidth ? 10 : 0)
                        .padding(.vertical, 10)
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
                    if nrPost.kind == 30023 {
                        ArticleView(nrPost, hideFooter: true)
//                            .background(
//                                Color.systemBackground
//                                    .cornerRadius(15)
//                            )
                            .roundedCorner(15, corners: [.allCorners])
//                            .overlay(
//                                RoundedRectangle(cornerRadius: 15)
//                                    .stroke(.regularMaterial, lineWidth: 1)
//                            )
                    }
                    else {
                        QuotedNoteFragmentView(nrPost: nrPost)
                    }
                }
                else {
                    Color.clear
                        .frame(height: 150)
                        .task {
                            DataProvider.shared().bg.perform {
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
                        L.og.info("🟢 Fetching for QuotedNoteFragmentView \(id)")
                        req(RM.getEventAndReferences(id: id))
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
            let _ = L.og.info("☠️☠️☠️☠️ NRPost() Kind1ById")
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
                    L.og.info("🟢 Fetching for Kind1ById \(id)")
                    req(RM.getEvent(id: id))
                }
        }
    }
}


struct ContentRenderer_Previews: PreviewProvider {
    
    static var previews: some View {
        
        PreviewContainer({ pe in
            pe.loadContacts()
            pe.loadPosts()
            pe.loadMedia()
        }) {
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
        }
    }
}

