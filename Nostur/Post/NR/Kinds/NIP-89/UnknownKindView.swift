////
////  UnknownKindView.swift
////  Nostur
////
////  Created by Fabian Lachman on 02/01/2024.
////
//
//import SwiftUI
//
//struct UnknownKindView: View {
//    private var nrPost: NRPost
//    private var theme: Theme
//    private var hideFooter: Bool
//    private var isDetail: Bool
//    private var isEmbedded: Bool
//    @StateObject private var model = UnknownKindModel()
//    
//    init(nrPost: NRPost, hideFooter: Bool = true, isDetail: Bool = false, isEmbedded: Bool, theme: Theme) {
//        self.nrPost = nrPost
//        self.theme = theme
//        self.hideFooter = hideFooter
//        self.isDetail = isDetail
//        self.isEmbedded = isEmbedded
//    }
//    
//    var body: some View {
//        if isEmbedded {
//            self.embeddedView
//        }
//        else {
//            self.normalView
//        }
//    }
//    
//    @ViewBuilder
//    var embeddedView: some View {
//        PostEmbeddedLayout(nrPost: nrPost, theme: theme) {
//            
//            content
//            
//        }
//    }
//    
//    @ViewBuilder
//    var normalView: some View {
//        PostLayout(nrPost: nrPost, hideFooter: hideFooter, isDetail: isDetail, theme: theme) {
//            
//            content
//            
//        }
//    }
//    
//    @ViewBuilder
//    var content: some View {
//        switch model.state {
//        case .loading:
//            CenteredProgressView()
//                .frame(height: 150)
//                .onAppear {
//                    model.load(unknownKind: nrPost.kind, eventId: nrPost.id, pubkey: nrPost.pubkey, dTag: nrPost.dTag, alt: nrPost.alt)
//                }
//        case .ready((let suggestedApps, let title)):
//            VStack(alignment: .leading) {
//                HStack {
//                    Text("\(Image(systemName: "app.fill")) \(title)")
//                        .fontWeight(.bold).lineLimit(1)
//                    Spacer()
////                    Button(action: showNip89Info, label: {
////                        Image(systemName: "questionmark.circle")
////                            .foregroundColor(theme.secondary)
////                            .font(.caption)
////                    })
//                }
//                if !suggestedApps.isEmpty {
//                    Text("Open with").font(.caption).foregroundColor(theme.secondary)
//                    Divider()
//                        .padding(.horizontal, -10)
//                    
//                    ForEach(suggestedApps) { app in
//                        AppRow(app: app,
//                               theme: theme
//                        )
//                    }
//                }
//                else {
//                    Text("\(Image(systemName: "exclamationmark.triangle.fill")) kind \(Double(nrPost.kind).clean) type not (yet) supported")
//                        .fontWeight(.bold).lineLimit(1)
//                    NRTextDynamic((nrPost.content ?? nrPost.alt) ?? "")
//                }
//            }
//            .padding(.horizontal, 10)
//            .padding(.vertical, 10)
//            .overlay(
//                RoundedRectangle(cornerRadius: 8)
//                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
//            )
//        case .timeout:
//            VStack {
//                Label(String(localized: "kind \(Double(nrPost.kind).clean) type not (yet) supported", comment: "Message shown when a 'kind X' post is not yet supported"), systemImage: "exclamationmark.triangle.fill")
//                    .hCentered()
//                    .frame(maxWidth: .infinity)
//                    .background(theme.lineColor.opacity(0.2))
//                NRTextDynamic((nrPost.content ?? nrPost.alt) ?? "")
//            }
//        }
//    }
//    
//    private func showNip89Info() {
//        
//    }
//}
//
