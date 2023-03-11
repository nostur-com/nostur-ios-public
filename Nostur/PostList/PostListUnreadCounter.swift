//
//  PostListUnreadCounter.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/03/2023.
//

import SwiftUI

struct PostListUnreadCounter: View {
    @ObservedObject var state:PostListModel
    
    var body: some View {
//        let _ = Self._printChanges()
        VStack {
            Spacer()
            HStack {
                Spacer()
                if (state.unreadCountSubject.value > 0) {
                    HStack {
                        Image(systemName: "arrow.down")
                        Text("\(state.unreadCountSubject.value) unread")
                        Image(systemName: "arrow.down")
                    }
                    .frame(minWidth: 30)
                    .padding(10)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .background(.blue)
                    .opacity(0.95)
                    .cornerRadius(20)
                    .onTapGesture {
                        sendNotification(.shouldScrollToLast)
                    }
                }
                Spacer()
            }
        }
    }
}

struct PostListUnreadCounterContainer: View {
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    
    var body: some View {
        let state = PostListModel.fromDb(pubkey: ns.account!.publicKey, listId: "Following", context: viewContext)

        PostListUnreadCounter(state:state)
    }
}

struct PostListUnreadCounter_Previews: PreviewProvider {
    static var previews: some View {
        PostListUnreadCounterContainer()
            .withPreviewEnvironment()
    }
}
