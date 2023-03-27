//
//  ListUnreadCounter.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/03/2023.
//

import SwiftUI

class LVMCounter: ObservableObject {
    @Published var unreadCount = 0
}

struct ListUnreadCounter: View {
    let vm:LVM
    @ObservedObject var vmCounter:LVMCounter
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                if (vmCounter.unreadCount > 0) {
                    HStack {
                        Image(systemName: "arrow.down")
                        Text("\(vmCounter.unreadCount) unread")
                        Image(systemName: "arrow.down")
                    }
                    .frame(minWidth: 30)
                    .padding(10)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .background(.blue)
                    .opacity(0.95)
                    .cornerRadius(20)
                    .shadow(radius: 90)
                    .onTapGesture {
                        vm.scrollToEnd()
                    }
                }
                Spacer()
            }
        }
    }
}
