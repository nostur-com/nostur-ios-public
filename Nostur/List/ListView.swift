//
//  ListView.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/03/2023.
//

import SwiftUI

struct ListView: View {
    @AppStorage("selected_subtab") var selectedSubTab = "Following"
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var dim:DIMENSIONS
    let vm:LVM
    
    var body: some View {
        let _ = Self._printChanges()
        if (vm.id == "Following" && ns.followingPublicKeys.count <= 1) {
            VStack {
                Spacer()
                Text("You are not following anyone yet, visit the explore tab and follow some people")
                    .multilineTextAlignment(.center)
                    .padding(.all, 30.0)

                Button {
                    selectedSubTab = "Explore"
                } label: {
                    Text("Explore")
                }.buttonStyle(.borderedProminent)
                Spacer()
            }
        }
        else {
            SmoothList(lvm: vm, dim: dim)
        }
    }
}
