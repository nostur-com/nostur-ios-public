//
//  Highlight.swift
//  Nostur
//
//  Created by Fabian Lachman on 11/05/2023.
//

import SwiftUI

// Hightlight note
struct Highlight: View {
    @ObservedObject private var pfpAttributes: NRPost.PFPAttributes
    @ObservedObject private var highlightAttributes: NRPost.HighlightAttributes
    @ObservedObject private var settings:SettingsStore = .shared
    
    private let nrPost:NRPost
    private let hideFooter:Bool // For rendering in NewReply
    private let missingReplyTo:Bool // For rendering in thread
    private var connect:ThreadConnectDirection? = nil // For thread connecting line between profile pics in thread
    private let grouped:Bool
    private var theme:Theme
    
    init(nrPost: NRPost, hideFooter:Bool = true, missingReplyTo:Bool = false, connect:ThreadConnectDirection? = nil, grouped:Bool = false, theme: Theme) {
        self.nrPost = nrPost
        self.pfpAttributes = nrPost.pfpAttributes
        self.highlightAttributes = nrPost.highlightAttributes
        self.hideFooter = hideFooter
        self.missingReplyTo = missingReplyTo
        self.connect = connect
        self.grouped = grouped
        self.theme = theme
    }
    
    private let THREAD_LINE_OFFSET = 24.0
    
    @State private var showMiniProfile = false
    @State private var lineLimit = 25
    
    var body: some View {
        
        HStack(alignment: .top, spacing: 10) {
            ZappablePFP(pubkey: nrPost.pubkey, contact: pfpAttributes.contact, size: DIMENSIONS.POST_ROW_PFP_WIDTH, zapEtag: nrPost.id, forceFlat: nrPost.isScreenshot)
                .frame(width: DIMENSIONS.POST_ROW_PFP_DIAMETER, height: DIMENSIONS.POST_ROW_PFP_DIAMETER)
                .background(alignment: .top) {
                    if connect == .top || connect == .both {
                        theme.lineColor
                            .frame(width: 2, height: 20)
                            .offset(x:0, y: -10)
                    }
                }
                .onTapGesture {
                    if !IS_APPLE_TYRANNY {
                        if let nrContact = pfpAttributes.contact {
                            navigateTo(nrContact)
                        }
                        else {
                            navigateTo(ContactPath(key: nrPost.pubkey))
                        }
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
                    ReplyingToFragmentView(nrPost: nrPost, theme: theme)
                        .contentShape(Rectangle())
                        .onTapGesture { navigateTo(nrPost) }
                }
                VStack {
                    Text(nrPost.content ?? "")
                        .lineLimit(lineLimit)
                        .onTapGesture(perform: {
                            withAnimation {
                                lineLimit = 150
                            }
                        })
//                        .fixedSize(horizontal: false, vertical: true)
                        .fontItalic()
                        .padding(20)
                        .overlay(alignment:.topLeading) {
                            Image(systemName: "quote.opening")
                                .foregroundColor(Color.secondary)
                        }
                        .overlay(alignment:.bottomTrailing) {
                            Image(systemName: "quote.closing")
                                .foregroundColor(Color.secondary)
                        }
                    
                    if let hlAuthorPubkey = highlightAttributes.authorPubkey {
                        HStack {
                            Spacer()
                            PFP(pubkey: hlAuthorPubkey, nrContact: highlightAttributes.contact, size: 20)
                                .onTapGesture {
                                    navigateTo(ContactPath(key: hlAuthorPubkey))
                                }
                            Text(highlightAttributes.anyName ?? "Unknown")
                                .onTapGesture {
                                    navigateTo(ContactPath(key: hlAuthorPubkey))
                                }
                        }
                        .padding(.trailing, 20)
                    }
                    HStack {
                        Spacer()
                        if let url = highlightAttributes.url {
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
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture {
                    navigateTo(nrPost)
                }
                if (!hideFooter && settings.rowFooterEnabled) {
                    CustomizableFooterFragmentView(nrPost: nrPost, theme: theme)
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
//                    .transaction { t in
//                        t.animation = nil
//                    }
            }
        }
    }
}

#Preview {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.parseMessages([
            ###"["EVENT","HL",{"pubkey":"fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52","content":"I looked you in the eye. “The meaning of life, the reason I made this whole universe, is for you to mature.”\n\n“You mean mankind? You want us to mature?”\n\n“No, just you. I made this whole universe for you. With each new life you grow and mature and become a larger and greater intellect.”","id":"d639ebbb2383d41bdcd9f73fe8a3d992ddd1fc2ef930d5dbe0149c6a1901568d","created_at":1694642512,"sig":"6ecdb176065691918340c703e84df03a477509d103e32848bb022165ae0a986fec5492fa542a02ba54173d4624414cae5159403a53336ac5f22c6ed5bb48dd70","kind":9802,"tags":[["r","https://xpressenglish.com/our-stories/the-egg-weir/"],["context","I looked you in the eye. “The meaning of life, the reason I made this whole universe, is for you to mature.” “You mean mankind? You want us to mature?” “No, just you. I made this whole universe for you. With each new life you grow and mature and become a larger and greater intellect.”"],["t","books"],["t","the egg"],["alt","\"I looked you in the eye. “The meaning of life, the reason I made this whole universe, is for you to mature.”\n\n“You mean mankind? You want us to mature?”\n\n“No, just you. I made this whole universe for you. With each new life you grow and mature and become a larger and greater intellect.”\"\n\nThis is a highlight created on https://highlighter.com"]]}]"###,
            ###"["EVENT","cf4f2b0a-9f24-4ca3-815c-f486b19ff9fe",{"content":"Shifting your mindset from waiting for things to be easy to embracing and understanding that fulfilling endeavors will always be challenging by default will be one of the better quality-of-life adjustments you can make in your thinking.","created_at":1682730290,"id":"6e00b687cdb567eda5093d54e6f73577ecae928f00a85c3b09dddbf2da52adc1","kind":9802,"pubkey":"0b963191ab21680a63307aedb50fd7b01392c9c6bef79cd0ceb6748afc5e7ffd","sig":"bb38b1b9318d8f30255ce0f71a95b42e1cd7aab8992b12e3736f78de4ec74d018e396620fb132e6701eca4824eb6e59e8e2d29929225d14f6f9983266bfa8eee","tags":[["r","https://habla.news/a/naddr1qqxnzd3cxy6rxvf5x5en2d3jqy2hwumn8ghj7un9d3shjtnyv9kh2uewd9hj7qghwaehxw309a3xjarrda5kuetj9eek7cmfv9kz7qg6waehxw309ac82unpwe5kgcfwdehhxarj9ekxzmny9uqkvamnwvaz7tmxd9k8getj9ehx7um5wgh8w6twv5hkuur4vgchqam5wfe8jer50yun2uf4vdjhxvr5ddknyu3hdp4hzen98948w7rgd4kk2ef40pmkkefkvu6xc73hxpkrwumy8pcxvdt58a38ymmpv33kzum58468yat9qyghwumn8ghj7mn0wd68ytnhd9hx2tczyp58rkxlp4p952c8anwrpga48law79xe45jh8lq4gf556e22jwtvzqcyqqq823cj04eew"],["a","30023:6871d8df0d425a2b07ecdc30a3b53ffaef14d9ad2573fc1542694d654a9396c1:1681431453562"],["p","0b963191ab21680a63307aedb50fd7b01392c9c6bef79cd0ceb6748afc5e7ffd"]]}]"###
        ])
    }) {
        SmoothListMock {
            if let nrPost = PreviewFetcher.fetchNRPost("6e00b687cdb567eda5093d54e6f73577ecae928f00a85c3b09dddbf2da52adc1") {
                Box {
                    Highlight(nrPost: nrPost, theme: Themes.default.theme)
                }
                
                Box {
                    Highlight(nrPost: nrPost, theme: Themes.default.theme)
                }
            }
        }
    }
}
