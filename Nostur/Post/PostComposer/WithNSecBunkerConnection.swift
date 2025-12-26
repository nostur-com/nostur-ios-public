//
//  NsecBunkerNewPost.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/08/2023.
//

import SwiftUI

struct WithNSecBunkerConnection<Content: View>: View {
    private let content: Content
    @ObservedObject private var remoteSigner: RemoteSignerManager = .shared
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
#if DEBUG
        let _ = nxLogChanges(of: Self.self)
#endif
        VStack {
            if remoteSigner.state == .error {
                Divider()
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                    Text("Remote signer appears offline, post will be saved but not published")
                        .fontWeight(.bold)
                }
                .padding(.horizontal, 10)
                Divider()
            }
            content
        }
        .task {
            if remoteSigner.state == .connected && remoteSigner.didRecentlyConnect {
                return
            }
            
            remoteSigner.state = .connecting
            remoteSigner.describe()
            remoteSigner.getPublicKey()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                if (remoteSigner.state != .connected) {
                    remoteSigner.state = .error
                }
            }
        }
    }
}
