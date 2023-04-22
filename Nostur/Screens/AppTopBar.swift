//
//  AppTopBar.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/02/2023.
//
import SwiftUI

struct AppTopBar: View {
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var sm:SideBarModel
    
    var body: some View {
        ZStack {
            HStack {
                if (ns.account != nil && !sm.showSidebar) {
                    Button {
                        sm.showSidebar.toggle()
                    } label: {
                        PFP(pubkey: ns.account!.publicKey, pictureUrl: ns.account?.picture, size:30)
                    }
                    .accessibilityLabel("Account menu")
                    .offset(x: 15)
                }
                Spacer()
            }
            HStack {
                Spacer()
                Image("NosturLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height:30)
                    .clipShape(Circle())
                Spacer()
            }
        }
    }
}

struct AppTopBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing:0) {
            AppTopBar()
                .withPreviewEnvironment()
            Spacer()
        }
    }
}
