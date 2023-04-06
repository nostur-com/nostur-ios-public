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
//    let vm:LVM
    @ObservedObject var vmCounter:LVMCounter
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
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
                    .background(Color("AccentColor"))
                    .opacity(0.95)
                    .cornerRadius(20)
                    .shadow(radius: 90)
                    .padding(.trailing, 10)
                    .padding(.top, 5)
                    .onTapGesture {
                        sendNotification(.shouldScrollToRecent)
                    }
                }
            }
            Spacer()
        }
    }
}

struct Previews_ListUnreadCounter_Previews: PreviewProvider {
    
    @StateObject static var lvmCounter = LVMCounter(count: 42)
    
    static var previews: some View {
        ListUnreadCounter(vmCounter: lvmCounter)
    }
}
