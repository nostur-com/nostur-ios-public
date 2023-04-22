//
//  ListUnreadCounter.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/03/2023.
//

import SwiftUI

class LVMCounter: ObservableObject {
    @Published var count = 0 // New one based on index
    
    init(count: Int = 0) {
        self.count = count
    }
}

struct ListUnreadCounter: View {
    @ObservedObject var vmCounter:LVMCounter
    
    var body: some View {
        if (vmCounter.count > 0) {
            // TODO: Add mini profile icons
            HStack {
                Text("\(vmCounter.count)")
                Image(systemName: "arrow.up")
            }
            .frame(minWidth: 30)
            .padding(10)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .foregroundColor(Color("AccentColor"))
                    .opacity(0.85)
                    .shadow(color: Color.gray.opacity(0.5), radius: 5)
            )
            .onTapGesture {
                sendNotification(.shouldScrollToRecent)
            }
        }
        else {
            EmptyView()
        }
    }
}

struct Previews_ListUnreadCounter_Previews: PreviewProvider {
    
    @StateObject static var lvmCounter = LVMCounter(count: 42)
    
    static var previews: some View {
        ListUnreadCounter(vmCounter: lvmCounter)
    }
}
