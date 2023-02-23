//
//  AppTopBar.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/02/2023.
//
import SwiftUI

struct AppTopBar: View {
    
    @EnvironmentObject var ns:NosturState
//    @EnvironmentObject var nav:NavigationModel
    var nav:NavigationModel = .shared
//    @Binding var showSidebar:Bool
    @State var appTopBarIsHidden = false
    
    var body: some View {
        ZStack {
            if (!appTopBarIsHidden) {
                HStack {
                    if (ns.account != nil && !nav.showSidebar) {
                        ProfilePicView(pubkey: ns.activeAccountPublicKey, account: ns.account, size:30)
                            .offset(x: 15)
                            .offset(y: -5)
                            .onTapGesture { nav.showSidebar.toggle() }
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
                        .offset(y: -5)
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
//    @State static var showSidebar = false
    static var previews: some View {
        AppTopBar()
            .withPreviewEnvironment()
    }
}
