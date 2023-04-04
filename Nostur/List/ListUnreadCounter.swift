//
//  ListUnreadCounter.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/03/2023.
//

import SwiftUI

class LVMCounter: ObservableObject {
    @Published var count = 0 // New one based on index
}

struct ListUnreadCounter: View {
    let vm:LVM
    @ObservedObject var vmCounter:LVMCounter
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                if (vmCounter.count > 0) {
                    HStack {
                        Image(systemName: "arrow.down")
                        Text("\(vmCounter.count) unread")
                        Image(systemName: "arrow.down")
                    }
                    .frame(minWidth: 30)
                    .padding(10)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .background(Color("AccentColor"))
                    .opacity(0.95)
                    .cornerRadius(20)
                    .shadow(radius: 90)
//                    .onTapGesture(count: 2, perform: {
//                     
//                    })
                    .onTapGesture {
                        vm.scrollToEnd()
                    }
//                    .onTapGesture(count: 2, perform: {
//                        vm.scrollToEnd()
//                    })
//                    .onTapGesture {
//                        vm.scrollABit()
//                    }
                }
                Spacer()
            }
        }
    }
}
