//
//  AppTopBar.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/02/2023.
//
import SwiftUI

struct AppTopBar: View {
    
    @EnvironmentObject var ns:NosturState
    @Binding var showMenu:Bool
    
    var body: some View {
        ZStack {
            HStack {
                if (ns.account != nil && !showMenu) {
                    ProfilePicView(pubkey: ns.activeAccountPublicKey, account: ns.account, size:30)
                        .offset(x: 30)
                        .onTapGesture { showMenu.toggle() }
                }
                Spacer()
            }
            HStack {
                Spacer()
                Image("NosturLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height:30)
                Spacer()
            }
        }
    }
}

struct AppTopBar_Previews: PreviewProvider {
    @State static var showMenu = false
    static var previews: some View {
        AppTopBar(showMenu: $showMenu)
            .withPreviewEnvironment()
    }
}
