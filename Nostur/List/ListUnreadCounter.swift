//
//  ListUnreadCounter.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/03/2023.
//

import SwiftUI

struct ListUnreadCounter: View {
    @ObservedObject var vm:ListViewModel
    
    var body: some View {
//        let _ = Self._printChanges()
        VStack {
            Spacer()
            HStack {
                Spacer()
                if (vm.unreadCountSubject.value > 0) {
                    HStack {
                        Image(systemName: "arrow.down")
                        Text("\(vm.unreadCountSubject.value) unread")
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
                        vm.scrollToEnd()
                    }
                }
                Spacer()
            }
        }
    }
}

struct ListUnreadCounterContainer: View {
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    
    var body: some View {
        let vm = ListViewModel.fromDB(pubkey: ns.activeAccountPublicKey, listId: "Following", pubkeys: ns.followingPublicKeys, context: viewContext)

        ListUnreadCounter(vm:vm)
    }
}

struct ListUnreadCounter_Previews: PreviewProvider {
    static var previews: some View {
        ListUnreadCounterContainer()
            .withPreviewEnvironment()
    }
}
