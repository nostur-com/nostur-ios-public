//
//  EmbedById.swift
//  Nostur
//
//  Created by Fabian Lachman on 21/09/2023.
//

import SwiftUI

struct EmbedById: View {
    @EnvironmentObject var theme:Theme
    public let id:String
    @StateObject private var vm = FetchVM<NRPost>(timeout: 2.5, debounceTime: 0.05)
    
    var body: some View {
        Group {
            switch vm.state {
            case .initializing, .loading, .altLoading:
                ProgressView()
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .task {
                        vm.setFetchParams((
                            prio: true,
                            req: { taskId in
                                bg().perform {
                                    if let event = try? Event.fetchEvent(id: self.id, context: bg()) {
                                        vm.ready(NRPost(event: event, withFooter: false))
                                    }
                                    else {
                                        req(RM.getEvent(id: self.id, subscriptionId: taskId))
                                    }
                                }
                            },
                            onComplete: { relayMessage, event in
                                if let event = event {
                                    vm.ready(NRPost(event: event, withFooter: false))
                                }
                                else if let event = try? Event.fetchEvent(id: self.id, context: bg()) {
                                    vm.ready(NRPost(event: event, withFooter: false))
                                }
                                else {
                                    vm.timeout()
                                }
                            },
                            altReq: nil
                        ))
                        vm.fetch()
                    }
            case .ready(let nrPost):
                if nrPost.kind == 30023 {
                    ArticleView(nrPost, hideFooter: true)
                        .padding(20)
                        .background(
                            Color(.secondarySystemBackground)
                                .cornerRadius(15)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(.regularMaterial, lineWidth: 1)
                        )
//                        .transaction { t in t.animation = nil }
//                        .debugDimensions("EmbedById.ArticleView")
                }
                else {
                    QuotedNoteFragmentView(nrPost: nrPost)
//                        .transaction { t in t.animation = nil }
//                        .debugDimensions("EmbedById.QuotedNoteFragmentView")
                }
            case .timeout:
                VStack {
                    Text("Unable to fetch content")
                    Button("Retry") { vm.fetch() }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .center)
            case .error(let error):
                Text(error)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(theme.lineColor.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    PreviewContainer({ pe in pe.loadPosts() }) {
        if let post = PreviewFetcher.fetchNRPost() {
            EmbedById(id: post.id)
        }
    }
}
