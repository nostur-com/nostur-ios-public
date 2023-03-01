//
//  UnreadCounter.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/02/2023.
//

import SwiftUI

struct UnreadCounter: View {
//    @ObservedObject var ds:DataStore = .shared
    @ObservedObject var ds:TimelineModel
    
    var body: some View {
        let _ = Self._printChanges()
        VStack {
            Spacer()
            HStack {
                Spacer()
                if (ds.unreadCount.value > 0) {
                    HStack {
                        Image(systemName: "arrow.down")
                        Text("\(ds.unreadCount.value) unread")
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
                        sendNotification(.shouldScrollToUnreadNote)
                    }
                }
                Spacer()
            }
        }
    }
}

struct UnreadCounter_Previews: PreviewProvider {
    static let ds = TimelineModel()
    static var previews: some View {
        UnreadCounter(ds:ds)
            .withPreviewEnvironment()
    }
}
