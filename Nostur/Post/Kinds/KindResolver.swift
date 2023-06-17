import SwiftUI

struct KindResolver: View {
    
    @ObservedObject var nrPost:NRPost
    var fullWidth:Bool = false
    var hideFooter:Bool = false // For rendering in NewReply
    var missingReplyTo:Bool = false // For rendering in thread
    var isReply:Bool = false 
    var isDetail:Bool = false
    var connect:ThreadConnectDirection? = nil
    var grouped:Bool = false
    
    var body: some View {
        VStack {
            if nrPost.isHighlight {
                Highlight(nrPost: nrPost, hideFooter: false, missingReplyTo:missingReplyTo, connect:connect, grouped: grouped)
            }
            else if fullWidth {
                Kind1(nrPost: nrPost, hideFooter:false, missingReplyTo: missingReplyTo, isDetail:isDetail, grouped: grouped)
            }
            else {
                Kind1Default(nrPost: nrPost, hideFooter:false, missingReplyTo: missingReplyTo, connect: connect, isDetail:isDetail, grouped: grouped)
            }
        }
        .onAppear {
            if !nrPost.missingPs.isEmpty {
                DataProvider.shared().bg.perform {
                    EventRelationsQueue.shared.addAwaitingEvent(nrPost.event, debugInfo: "KindResolver.001")
                    QueuedFetcher.shared.enqueue(pTags: nrPost.missingPs)
                }
            }
        }
        .onDisappear {
            if !nrPost.missingPs.isEmpty {
                QueuedFetcher.shared.dequeue(pTags: nrPost.missingPs)
            }
        }
        
    }
}

struct KindResolver_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            VStack {
                if let nrPost = PreviewFetcher.fetchNRPost() {
                    KindResolver(nrPost: nrPost)
                }
            }
        }
    }
}
