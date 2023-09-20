//
//  DetailTab.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/02/2023.
//

import SwiftUI

struct DetailTab: View {
    @EnvironmentObject private var theme:Theme
    @State private var navPath = NavigationPath()
    private let tm:DetailTabsModel = .shared
    @ObservedObject public var tab:TabModel
    
    var body: some View {
        NavigationStack(path: $navPath) {
            if let nrPost = tab.nrPost {
                ZStack {
                    theme.listBackground
                        .ignoresSafeArea()
                    PostDetailView(nrPost: nrPost, navTitleHidden: true)
                        .withNavigationDestinations()
                }
            }
            else if let nrContact = tab.nrContact {
                ZStack {
                    theme.listBackground
                        .ignoresSafeArea()
                    ProfileView(nrContact:nrContact, tab: tab.profileTab)
                        .withNavigationDestinations()
                }
            }
            else if let notePathId = tab.notePath?.id {
                ZStack {
                    theme.listBackground
                        .ignoresSafeArea()
                    NoteById(id: notePathId)//.opacity(tm.selected == tab ? 1 : 0)
                        .withNavigationDestinations()
                }
                
            }
            else if let naddr1 = tab.naddr1?.naddr1 {
                ZStack {
                    theme.listBackground
                        .ignoresSafeArea()
                    ArticleByNaddr(naddr1: naddr1)
                        .withNavigationDestinations()
                }
                
            }
            else if let articleId = tab.articlePath?.id {
                ZStack {
                    theme.listBackground
                        .ignoresSafeArea()
                    ArticleById(id: articleId)
                        .withNavigationDestinations()
                }
                
            }
            else if let contactPubkey = tab.contactPath?.key {
                ZStack {
                    theme.listBackground
                        .ignoresSafeArea()
                    ProfileByPubkey(pubkey: contactPubkey, tab: tab.contactPath?.tab)//.opacity(tm.selected == tab ? 1 : 0)
                        .withNavigationDestinations()
                }
                
            }
            else if let nrContact = tab.nrContactPath?.nrContact {
                ZStack {
                    theme.listBackground
                        .ignoresSafeArea()
                    ProfileView(nrContact:nrContact, tab: tab.profileTab)
                        .withNavigationDestinations()
                }
                
            }
            else {
                EmptyView()
            }
        }
        .onReceive(receiveNotification(.navigateTo)) { notification in
            guard tm.selected == tab else { return }
            let destination = notification.object as! NavigationDestination
            guard type(of: destination.destination) != HashtagPath.self else  { return }
            navPath.append(destination.destination)
        }
    }
}

struct DetailTab_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadPosts() }, previewDevice: PreviewDevice(rawValue: "iPad Air (5th generation)")) {
            if let post = PreviewFetcher.fetchNRPost() {
                DetailTab(tab: TabModel(nrPost: post))
            }
        }
    }
}
