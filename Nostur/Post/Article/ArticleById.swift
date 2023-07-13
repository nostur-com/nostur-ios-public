//
//  ArticleById.swift
//  Nostur
//
//  Created by Fabian Lachman on 20/06/2023.
//

import SwiftUI

struct ArticleById: View {
    let id:String
    var navigationTitle:String? = nil
    @State var article:NRPost? = nil
    @State var backlog = Backlog(timeout: 15, auto: true)
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
                    .onAppear {
                        DataProvider.shared().bg.perform {
                            if let article = try? Event.fetchEvent(id: id, context: DataProvider.shared().bg) {
                                let article = NRPost(event: article)
                                DispatchQueue.main.async {
                                    self.article = article
                                }
                            }
                            else {
                                let reqTask = ReqTask(
                                    prefix: "ARTICLE-",
                                    reqCommand: { taskId in
                                        req(RM.getEvent(id: id, subscriptionId: taskId))
                                    },
                                    processResponseCommand: { taskId, _ in
                                        DataProvider.shared().bg.perform {
                                            if let article = try? Event.fetchEvent(id: id, context: DataProvider.shared().bg) {
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
                                
                                backlog.add(reqTask)
                                reqTask.fetch()
                            }
                        }
                    }
            }
        }
    }
}
