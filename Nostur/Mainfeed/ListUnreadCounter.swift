//
//  ListUnreadCounter.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/03/2023.
//

import SwiftUI

class LVMCounter: ObservableObject {
    @Published var count = 0 // New one based on index
    @Published var unreadIds: [String: Int] = [:] // Dict of [post id: posts count (post + parent posts)]
    
    public var unreadCount: Int {
        unreadIds.reduce(0, { $0 + $1.value })
    }
    
    init(count: Int = 0) {
        self.count = count
    }
}

struct ListUnreadCounter: View {
    private var vm: LVM
    @ObservedObject private var vmCounter: LVMCounter
    private var theme: Theme
    
    init(vm: LVM, theme: Theme) {
        self.vm = vm
        self.vmCounter = vm.lvmCounter
        self.theme = theme
    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        // TODO: Add mini profile icons
        RoundedRectangle(cornerRadius: 20)
            .foregroundColor(theme.accent)
//            .opacity(0.85)
//            .shadow(color: Color.gray.opacity(0.5), radius: 5)
            .frame(width: 65, height: 40)
            .overlay(alignment: .leading) {
                Text(String(vmCounter.unreadCount))
                    .animation(.snappy, value: vmCounter.unreadCount)
                    .rollingNumber()
                    .fixedSize()
                    .frame(width: 35, alignment: .center)
                    .padding(.leading, 5)
                    
            }
            .overlay(alignment: .trailing) {
                Image(systemName: "arrow.up")
                    .padding(.trailing, 8)
            }
//            .padding(0)
            .fontWeightBold()
            .foregroundColor(.white)

            .opacity(vmCounter.unreadCount > 0 ? 1.0 : 0)
//            .onTapGesture {
//                sendNotification(.shouldScrollToFirstUnread)
//            }
//            .simultaneousGesture(LongPressGesture().onEnded { _ in
//                sendNotification(.shouldScrollToTop)
//            })
            .onChange(of: vmCounter.unreadCount) { newUnreadCount in
                if newUnreadCount == 0 && vmCounter.unreadCount != 0 {
                    vmCounter.unreadIds = [:]
                    L.og.debug("UNREAD COUNTER RESET")
                }
            }
    }
}

struct Previews_ListUnreadCounter_PreviewsWrapper: View {
    
    @StateObject var lvm = LVM(type: .pubkeys, pubkeys: [], listId: "Explore")
    
    var body: some View {
        VStack {
            ListUnreadCounter(vm: lvm, theme: Themes.default.theme)
            
            Button("Add +7") {
                lvm.lvmCounter.count += 7
            }
            .padding(.top, 30)
        }
        .onAppear {
            lvm.lvmCounter.count = 17
        }
    }
}

#Preview("Unread counter") {
    Previews_ListUnreadCounter_PreviewsWrapper()
        .previewDevice(PreviewDevice(rawValue: PREVIEW_DEVICE))
}
