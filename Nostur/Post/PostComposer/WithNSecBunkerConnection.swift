//
//  NsecBunkerNewPost.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/08/2023.
//

import SwiftUI

struct WithNSecBunkerConnection<Content: View>: View {
    let content: Content
    @ObservedObject var nsecBunker:NSecBunkerManager
    
    init(nsecBunker: NSecBunkerManager, @ViewBuilder content: ()->Content) {
        self.nsecBunker = nsecBunker
        self.content = content()
    }
    
    var body: some View {
        VStack {
            if nsecBunker.state == .error {
                Divider()
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                    Text("nsecBunker appears offline, post will be saved but not published")
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 10)
                Divider()
            }
            content
                .task {
                    nsecBunker.state = .connecting
                    nsecBunker.describe()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                        if (nsecBunker.state != .connected) {
                            nsecBunker.state = .error
                        }
                    }
                }
        }
        .onDisappear {
            nsecBunker.state = .disconnected
        }
    }
}
