//
//  MainView.swift
//  Nostur
//
//  Created by Fabian Lachman on 31/01/2023.
//

import SwiftUI
import Introspect

struct NosturRootMenu: View {
    
//    @EnvironmentObject var nav:NavigationModel
    let nav:NavigationModel = .shared
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var sm:SideBarModel
//    @EnvironmentObject var sp:SocketPool
    
    @State var accountsSheetIsShown = false
    
    var body: some View {
        let _ = Self._printChanges()
        SideBarStack(sidebarWidth: 310) {
            if (ns.account != nil) {
                sideBar
                    .withNavigationDestinations() //TODO: Put back?
            }
        } content: {
            if (ns.account != nil) {
                NosturTabsView()
                    .onOpenURL { url in
                        self.handleUrl(url)
                    }
            }
        }
        .sheet(isPresented: $accountsSheetIsShown) {
            AccountsSheet()
                .presentationDetents([.fraction(0.45), .medium, .large])
//                .presentationDragIndicator(.hidden)
        }
        .onReceive(receiveNotification(.willDeleteAllEvents)) { _ in
            ns.setAccount()
        }
//        .edgesIgnoringSafeArea(.all)
    }
}
extension NosturRootMenu {
    
    private var sideBar: some View {
        VStack(alignment: .leading) {
            let _ = Self._printChanges()
            List {
                HStack(spacing: 10) {
                    ProfilePicView(pubkey: ns.account!.publicKey, account: ns.account!)
                    Spacer()
                    FastAccountSwitcher()
                    Button { accountsSheetIsShown = true } label: {
                        Image(systemName: "ellipsis.circle")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 25, height: 25)
                    }
//                    .buttonStyle(.bordered)
//                    .buttonBorderShape(.capsule)
                }
                
                Text("\(ns.account!.display_name != "" ? ns.account!.display_name : ns.account!.name)").font(.headline)
                Text("@\(ns.account!.name)").font(.subheadline)
                Text(try! AttributedString(markdown: "**\(ns.account?.follows?.count ?? 0)**  Following")).font(.caption)
                
                Button {
                    nav.navigateTo(ContactPath(key: ns.account!.publicKey))
                    sm.showSidebar = false
                } label: {
                    Label("Profile", systemImage: "person")
                }
                Button {
                    nav.navigateTo(ViewPath.Bookmarks(account: ns.account!))
                    sm.showSidebar = false
                } label: {
                    Label("Bookmarks", systemImage: "bookmark")
                }
                Button {
                    nav.navigateTo(ViewPath.Badges)
                    sm.showSidebar = false
                } label: {
                    Label("Badges", systemImage: "trophy.circle")
                }
                Button {
                    nav.navigateTo(ViewPath.Settings)
                    sm.showSidebar = false
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                Button {
                    nav.navigateTo(ViewPath.Blocklist)
                    sm.showSidebar = false
                } label: {
                    Label("Block list", systemImage: "person.badge.minus")
                }
                Button {} label: {
                    Label("About", systemImage: "info")
                }
            }.listStyle(.plain)
                .introspect(selector: TargetViewSelector.ancestorOrSiblingContaining, customize: { (collectionView: UICollectionView) in
                    guard #available(iOS 16, *) else { return }
                    var config = UICollectionLayoutListConfiguration(appearance: .plain)
                    config.showsSeparators = false
                    let layout = UICollectionViewCompositionalLayout.list(using: config)
                    collectionView.collectionViewLayout = layout
                })
            Spacer()
        }
    }

    func handleUrl(_ url:URL) {
        // TODO: CHECK INPUT!!! SECURITY!
        print(url.absoluteString)
        // LINKS FROM ANYWHERE (NPUB1/NOTE1)
        let nostr = url.absoluteString.matchingStrings(regex: "^(nostr:)(npub1|note1)([023456789acdefghjklmnpqrstuvwxyz]{58})$")
        if nostr.count == 1 && nostr[0].count == 4 {
            print("ok lets go to: \(nostr[0][2])\(nostr[0][3])")
            let key = try! NIP19(displayString: "\(nostr[0][2])\(nostr[0][3])")
            print("ok lets go to: \(key.hexString)")
            if nostr[0][2] == "npub1" {
                nav.navigateTo(ContactPath(key: key.hexString))
            }
            if nostr[0][2] == "note1" {
                nav.navigateTo(NotePath(id: key.hexString))
            }
        }
        
        // LINKS FROM WITHIN NOSTUR
        let nostur = url.absoluteString.matchingStrings(regex: "^(nostur:)(p:|e:)([0-9a-z]{64})$")
        if nostur.count == 1 && nostur[0].count == 4 {
            print("ok lets go to: \(nostur[0][2])\(nostur[0][3])")
            if nostur[0][2] == "p:" {
                nav.navigateTo(ContactPath(key: nostur[0][3]))
            }
            if nostur[0][2] == "e:" {
                nav.navigateTo(NotePath(id: nostur[0][3]))
            }
        }
        
        // LINKS FROM ANYWHERE (HEX)
        let nostrHex = url.absoluteString.matchingStrings(regex: "^(nostr:)(p:|e:)([0-9a-z]{64})$")
        if nostrHex.count == 1 && nostrHex[0].count == 4 {
            print("ok lets go to: \(nostrHex[0][2])\(nostrHex[0][3])")
            if nostrHex[0][2] == "p:" {
                nav.navigateTo(ContactPath(key: nostrHex[0][3]))
            }
            if nostrHex[0][2] == "e:" {
                nav.navigateTo(NotePath(id: nostrHex[0][3]))
            }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        NosturRootMenu()
            .withPreviewEnvironment()
    }
}
