//
//  ReplyingToFragment.swift
//  Nostur
//
//  Created by Fabian Lachman on 27/01/2023.
//

import SwiftUI
import Combine

struct ReplyingToFragmentView: View {
    
    @Environment(\.managedObjectContext) var viewContext
    private let sp:SocketPool = .shared
    
    let vPost:VPost
    @ObservedObject var event:Event
    @State var rendered:AttributedString?
    @State var subscriptions = Set<AnyCancellable>()
    
    init(vPost: VPost) {
        self.vPost = vPost
        self.event = vPost.event
        _rendered = State(initialValue: vPost.replyingToUsernamesMarkDown)
    }
    
    var body: some View {
        Group {
            if let rendered = rendered {
                Text(rendered)
                        .fontWeight(.light)
                        .foregroundColor(.secondary)
                        .accentColor(Color("AccentColor"))
                        .tint(Color("AccentColor"))
                        .frame(maxWidth:.infinity, alignment: .leading)
                }
        }
//        .onChange(of: event) { newValue in
//            if (event.contacts?.count ?? 0) != (newValue.contacts?.count ?? 0) {
//                let textRenderer = TextRenderer(viewContext, event:event)
//                rendered = textRenderer.replyingToUsernamesMarkDownString(event)
//                print("rendered: \(event.id)")
//            }
//        }
        .onAppear {
            event.objectWillChange
                .sink {
                    let textRenderer = TextRenderer(viewContext, event:event)
                    let replyingToMD = textRenderer.replyingToUsernamesMarkDownString(event)
                    rendered = replyingToMD != nil ? try! AttributedString(markdown: replyingToMD!) : nil
                }
                .store(in: &subscriptions)
        }
    }
}

struct ReplyingToFragmentView_Previews: PreviewProvider {
    static var previews: some View {
        
        VStack {
            // No replyTo.contact
            let event1 = PreviewFetcher.fetchVPost("dec5a86ad780edd26fb8a1b85f919ddace9cb2b2b5d3a68d5124802fc2da4ed3")
            
            // With replyTo.contact
            let event2 = PreviewFetcher.fetchVPost("f985347c50a24e94277ae4d33b391191e2eabcba31d0553adfafafb18ca2727e")
            
            // No reply at all.
            let event3 = PreviewFetcher.fetchVPost("d90c63ca06c0eab08d5c79d3991cd22b6c0e2f4e56167ae918343f2a9bc98ff1")
            
            if (event1 != nil) {
                ReplyingToFragmentView(vPost: event1!)
                Spacer()
            }
        
            if (event2 != nil) {
                ReplyingToFragmentView(vPost: event2!)
                Spacer()
            }
            
            if (event3 != nil) {
                ReplyingToFragmentView(vPost: event3!)
                Spacer()
            }
        }
        .withPreviewEnvironment()
        
    }
}
