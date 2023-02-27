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
    @EnvironmentObject var sm:SideBarModel
    var nav:NavigationModel = .shared
//    @Binding var showSidebar:Bool
//    @State var appTopBarIsHidden = false
    
    var body: some View {
        ZStack {
//            if (!appTopBarIsHidden) {
                HStack {
                    if (ns.account != nil && !sm.showSidebar) {
                        ProfilePicView(pubkey: ns.activeAccountPublicKey, account: ns.account, size:30)
                            .offset(x: 15)
                            .offset(y: -5)
                            .onTapGesture { sm.showSidebar.toggle() }
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
//            }
        }
//        // TODO: FIXEN: NAV IS NIET MET OBSERVED
//        .onChange(of: nav.selectedTab) { tab in
//            if (tab == "Timeline") && (nav.timelinePath.isEmpty) {
//                withAnimation(Animation.easeInOut(duration: 0.1)) {
//                    appTopBarIsHidden = false
//                }
//            }
//            else {
//                withAnimation(Animation.easeInOut(duration: 0.1)) {
//                    appTopBarIsHidden = true
//                }
//            }
//        }
//        .onChange(of: nav.timelinePath) { newValue in
//            withAnimation(Animation.easeInOut(duration: 0.1)) {
//                appTopBarIsHidden = !newValue.isEmpty
//            }
//        }
    }
}

struct AppTopBar_Previews: PreviewProvider {
//    @State static var showSidebar = false
    static var previews: some View {
        VStack {
            AppTopBar()
                .withPreviewEnvironment()
            Spacer()
        }
    }
}
