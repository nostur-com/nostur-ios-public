//
//  AppTopBar.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/02/2023.
//
import SwiftUI

struct AppTopBar: View {
    
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var nav:NavigationModel
    @Binding var showMenu:Bool
    @State var appTopBarIsHidden = false
    
    var body: some View {
        ZStack {
            if (!appTopBarIsHidden) {
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
                        .clipShape(Circle())
                    Spacer()
                }
            }
        }
        .onChange(of: nav.selectedTab) { tab in
            if (tab == "Timeline") && (nav.timelinePath.isEmpty) {
                withAnimation(Animation.easeInOut(duration: 0.1)) {
                    appTopBarIsHidden = false
                }
            }
            else {
                withAnimation(Animation.easeInOut(duration: 0.1)) {
                    appTopBarIsHidden = true
                }
            }
        }
        .onChange(of: nav.timelinePath) { newValue in
            withAnimation(Animation.easeInOut(duration: 0.1)) {
                appTopBarIsHidden = !newValue.isEmpty
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
