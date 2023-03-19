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
//    @State var unreadCount = 0
    
    var body: some View {
//        let _ = Self._printChanges()
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
//        .onReceive(receiveNotification(.updateUnreadCount)) { notification in
//            unreadCount = notification.object as! Int
//        }
    }
}

//struct ListUnreadCounterContainer: View {
//    @Environment(\.managedObjectContext) var viewContext
//    @EnvironmentObject var ns:NosturState
//    
//    
//    var body: some View {
//        let vm = LVM(pubkey: ns.activeAccountPublicKey, pubkeys: ns.followingPublicKeys, listId: "Following")
//
//        ListUnreadCounter(vm:vm)
//    }
//}
//
//struct ListUnreadCounter_Previews: PreviewProvider {
//    static var previews: some View {
//        ListUnreadCounterContainer()
//            .withPreviewEnvironment()
//    }
//}
