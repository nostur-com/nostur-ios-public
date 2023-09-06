//
//  Highlight.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/05/2023.
//

import SwiftUI

// Hightlight note
struct Highlight: View {
    @EnvironmentObject var theme:Theme
    let nrPost:NRPost
    @ObservedObject var pfpAttributes: NRPost.PFPAttributes
    let hideFooter:Bool // For rendering in NewReply
    let missingReplyTo:Bool // For rendering in thread
    var connect:ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    let grouped:Bool
    @ObservedObject var settings:SettingsStore = .shared
    
    init(nrPost: NRPost, hideFooter:Bool = true, missingReplyTo:Bool = false, connect:ThreadConnectDirection? = nil, grouped:Bool = false) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.grouped = grouped
    }
    
    let THREAD_LINE_OFFSET = 24.0
    
    @State var showMiniProfile = false
    
    var body: some View {
        
        HStack(alignment: .top, spacing: 10) {
            ZappablePFP(pubkey: nrPost.pubkey, contact: pfpAttributes.contact, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: nrPost.id)
                .frame(width: DIMENSIONS.POST_ROW_PFP_WIDTH, height: DIMENSIONS.POST_ROW_PFP_HEIGHT)
                .background(alignment: .top) {
                    if connect == .top || connect == .both {
                        theme.lineColor
                            .frame(width: 2, height: 20)
                            .offset(x:0, y: -10)
                    }
                }
                .onTapGesture {
                    if !IS_APPLE_TYRANNY {
                        navigateTo(ContactPath(key: nrPost.pubkey))
                    }
                    else {
                        withAnimation {
                            showMiniProfile = true
                        }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if (showMiniProfile) {
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    sendNotification(.showMiniProfile,
                                                     MiniProfileSheetInfo(
                                                        pubkey: nrPost.pubkey,
                                                        contact: nrPost.contact,
                                                        zapEtag: nrPost.id,
                                                        location: geo.frame(in: .global).origin
                                                     )
                                    )
                                    showMiniProfile = false
                                }
                        }
                        .frame(width: 10)
                        .zIndex(100)
                        .transition(.asymmetric(insertion: .scale(scale: 0.4), removal: .opacity))
                        .onReceive(receiveNotification(.dismissMiniProfile)) { _ in
                            showMiniProfile = false
                        }
                    }
                }
            
            VStack(alignment:.leading, spacing: 3) {// Post container
                HStack { // name + reply + context menu
                    NoteHeaderView(nrPost: nrPost)
                    Spacer()
                    LazyNoteMenuButton(nrPost: nrPost)
                }
                if missingReplyTo {
                    ReplyingToFragmentView(nrPost: nrPost)
                        .contentShape(Rectangle())
                        .onTapGesture { navigateTo(nrPost) }
                }
                VStack {
                    Text(nrPost.content ?? "")
                        .lineLimit(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .italic()
                        .padding(20)
                        .overlay(alignment:.topLeading) {
                            Image(systemName: "quote.opening")
                                .foregroundColor(Color.secondary)
                        }
                        .overlay(alignment:.bottomTrailing) {
                            Image(systemName: "quote.closing")
                                .foregroundColor(Color.secondary)
                        }
                    
                    if let hl = nrPost.highlightData, let hlPubkey = hl.highlightAuthorPubkey {
                        HStack {
                            Spacer()
                            PFP(pubkey: hlPubkey, nrContact: hl.highlightNrContact, size: 20)
                                .onTapGesture {
                                    navigateTo(ContactPath(key: hlPubkey))
                                }
                            Text(hl.highlightAuthorName ?? "Unknown")
                                .onTapGesture {
                                    navigateTo(ContactPath(key: hlPubkey))
                                }
                        }
                        .padding(.trailing, 20)
                    }
                    HStack {
                        Spacer()
                        if let url = nrPost.highlightData?.highlightUrl {
                            Text("[\(url)](\(url))")
                                .lineLimit(1)
                                .font(.caption)
                        }
                    }
                    .padding(.trailing, 20)
                }
                .padding(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(theme.lineColor.opacity(0.2), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    navigateTo(nrPost)
                }
                if (!hideFooter && settings.rowFooterEnabled) {
                    FooterFragmentView(nrPost: nrPost)
                        .padding(.top, 10)
                }
            }
            .padding(.bottom, 10)
        }
        .background(alignment: .leading) {
            if connect == .bottom || connect == .both {
                theme.lineColor
                    .frame(width: 2)
                    .opacity(0.2)
                    .offset(x: THREAD_LINE_OFFSET, y: 20)
                    .transaction { t in
                        t.animation = nil
                    }
            }
        }
    }
}

struct Highlight_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in
            pe.parseMessages([
                ###"["EVENT","cf4f2b0a-9f24-4ca3-815c-f486b19ff9fe",{"content":"Shifting your mindset from waiting for things to be easy to embracing and understanding that fulfilling endeavors will always be challenging by default will be one of the better quality-of-life adjustments you can make in your thinking.","created_at":1682730290,"id":"6e00b687cdb567eda5093d54e6f73577ecae928f00a85c3b09dddbf2da52adc1","kind":9802,"pubkey":"0b963191ab21680a63307aedb50fd7b01392c9c6bef79cd0ceb6748afc5e7ffd","sig":"bb38b1b9318d8f30255ce0f71a95b42e1cd7aab8992b12e3736f78de4ec74d018e396620fb132e6701eca4824eb6e59e8e2d29929225d14f6f9983266bfa8eee","tags":[["r","https://habla.news/a/naddr1qqxnzd3cxy6rxvf5x5en2d3jqy2hwumn8ghj7un9d3shjtnyv9kh2uewd9hj7qghwaehxw309a3xjarrda5kuetj9eek7cmfv9kz7qg6waehxw309ac82unpwe5kgcfwdehhxarj9ekxzmny9uqkvamnwvaz7tmxd9k8getj9ehx7um5wgh8w6twv5hkuur4vgchqam5wfe8jer50yun2uf4vdjhxvr5ddknyu3hdp4hzen98948w7rgd4kk2ef40pmkkefkvu6xc73hxpkrwumy8pcxvdt58a38ymmpv33kzum58468yat9qyghwumn8ghj7mn0wd68ytnhd9hx2tczyp58rkxlp4p952c8anwrpga48law79xe45jh8lq4gf556e22jwtvzqcyqqq823cj04eew"],["a","30023:6871d8df0d425a2b07ecdc30a3b53ffaef14d9ad2573fc1542694d654a9396c1:1681431453562"],["p","0b963191ab21680a63307aedb50fd7b01392c9c6bef79cd0ceb6748afc5e7ffd"]]}]"###
            ])
        }) {
            SmoothListMock {
                if let nrPost = PreviewFetcher.fetchNRPost("6e00b687cdb567eda5093d54e6f73577ecae928f00a85c3b09dddbf2da52adc1") {
                    Box {
                        Highlight(nrPost: nrPost)
                    }
                    
                    Box {
                        Highlight(nrPost: nrPost)
                    }
                }
            }
        }
    }
}
