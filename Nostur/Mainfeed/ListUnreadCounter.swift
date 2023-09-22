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
    @EnvironmentObject private var theme:Theme
    private var vm:LVM
    @ObservedObject private var vmCounter:LVMCounter
    
    init(vm: LVM) {
        self.vm = vm
        self.vmCounter = vm.lvmCounter
    }
    
    var body: some View {
        // TODO: Add mini profile icons
        RoundedRectangle(cornerRadius: 20)
            .foregroundColor(theme.accent)
            .opacity(0.85)
            .shadow(color: Color.gray.opacity(0.5), radius: 5)
            .frame(width: 65, height: 40)
            .overlay(alignment: .leading) {
                Text(String(vmCounter.count))
                    .fixedSize()
                    .frame(width: 35, alignment: .center)
                    .padding(.leading, 5)
                    
            }
            .overlay(alignment: .trailing) {
                Image(systemName: "arrow.up")
                    .padding(.trailing, 10)
            }
            .padding(10)
            .fontWeight(.bold)
            .foregroundColor(.white)

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
            
            Button("Add +7") {
                lvm.lvmCounter.count += 7
            }
            .padding(.top, 30)
        }
        .onAppear {
            lvm.lvmCounter.count = 7
        }
    }
}

#Preview("Unread counter") {
    Previews_ListUnreadCounter_PreviewsWrapper()
        .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
        .environmentObject(Theme.default)
}
