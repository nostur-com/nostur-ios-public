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
    @EnvironmentObject var theme:Theme
    var vm:LVM
    @ObservedObject var vmCounter:LVMCounter
    
    init(vm: LVM) {
        self.vm = vm
        self.vmCounter = vm.lvmCounter
    }
    
    var body: some View {
        // TODO: Add mini profile icons
        HStack {
            Text(String(vmCounter.count))
            Image(systemName: "arrow.up")
        }
        .frame(minWidth: 30)
        .padding(10)
        .fontWeight(.bold)
        .foregroundColor(.white)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .foregroundColor(theme.accent)
                .opacity(0.85)
                .shadow(color: Color.gray.opacity(0.5), radius: 5)
        )
        .opacity(vmCounter.count > 0 ? 1.0 : 0)
        .onTapGesture {
            sendNotification(.shouldScrollToFirstUnread)
        }
        .simultaneousGesture(LongPressGesture().onEnded { _ in
            sendNotification(.shouldScrollToTop)
        })
    }
}

struct Previews_ListUnreadCounter_PreviewsWrapper: View {
    
    @StateObject var lvm = LVM(type: .pubkeys, pubkeys: [], listId: "Explore")
    
    var body: some View {
        VStack {
            ListUnreadCounter(vm: lvm)
            
            Button("Add +1") {
                lvm.lvmCounter.count += 1
            }
            .padding(.top, 30)
        }
        .onAppear {
            lvm.lvmCounter.count = 7
        }
    }
}

struct Previews_ListUnreadCounter_Previews: PreviewProvider {
    static var previews: some View {
        Previews_ListUnreadCounter_PreviewsWrapper()
            .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
            .environmentObject(Theme.default)
    }
}
