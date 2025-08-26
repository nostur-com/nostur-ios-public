//
//  ArticleById.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/06/2023.
//

import SwiftUI

struct ArticleById: View {
    @Environment(\.theme) private var theme
    public let id:String
    public var navigationTitle:String? = nil
    public var navTitleHidden: Bool = false
    @State var article:NRPost? = nil
    @State var backlog = Backlog(timeout: 15, auto: true, backlogDebugName: "ArticleById")
    @State var error:String? = nil
    
    var body: some View {
        VStack {
            if let error  {
                Text(error)
            }
            else if let article {
                ArticleView(article, isDetail: true)
//                    .background(Color(.secondarySystemBackground))
            }
            else {
                ProgressView()
                    .onAppear { [weak backlog] in
                        bg().perform {
                            if let article = Event.fetchEvent(id: id, context: bg()) {
                                let article = NRPost(event: article)
                                DispatchQueue.main.async {
                                    self.article = article
                                }
                            }
                            else {
                                let reqTask = ReqTask(
                                    prio: true,
                                    prefix: "ARTICLE-",
                                    reqCommand: { taskId in
                                        req(RM.getEvent(id: id, subscriptionId: taskId))
                                    },
                                    processResponseCommand: { taskId, _, article in
                                        bg().perform {
                                            guard let backlog else { return }
                                            if let article = article {
                                                let article = NRPost(event: article)
                                                DispatchQueue.main.async {
                                                    self.article = article
                                                }
                                                backlog.clear()
                                            }
                                            else if let article = Event.fetchEvent(id: id, context: bg()) {
                                                let article = NRPost(event: article)
                                                DispatchQueue.main.async {
                                                    self.article = article
                                                }
                                                backlog.clear()
                                            }
                                        }
                                    },
                                    timeoutCommand: { taskId in
                                        DispatchQueue.main.async {
                                            self.error = "Could not find article"
                                        }
                                    })
                                
                                guard let backlog else { return }
                                backlog.add(reqTask)
                                reqTask.fetch()
                            }
                        }
                    }
            }
        }
    }
}
