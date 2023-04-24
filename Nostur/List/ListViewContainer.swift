//
//  ListViewContainer.swift
//  Nostur
//
//  Created by Fabian Lachman on 01/04/2023.
//



import SwiftUI

struct ListViewContainer: View {
    
    let vm:LVM    
    
    var body: some View {
        let _ = Self._printChanges()
        ListView(vm:vm)
            .overlay(alignment: .topTrailing) {
                ListUnreadCounter(vmCounter: vm.lvmCounter)
                    .padding(.trailing, 10)
                    .padding(.top, 5)
            }

        .background(Color("ListBackground"))
    }
}

enum ListType {
    case account
    case explore
    case list
}
