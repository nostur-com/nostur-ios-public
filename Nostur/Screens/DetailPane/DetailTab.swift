//
//  DetailTab.swift
//  Nostur
//
//  Created by Fabian Lachman on 28/02/2023.
//

import SwiftUI
import NavigationBackport

struct DetailTab: View {
    @EnvironmentObject private var dim: DIMENSIONS
    @EnvironmentObject private var themes: Themes
    @State private var navPath = NBNavigationPath()
    @EnvironmentObject private var tm: DetailTabsModel
    @ObservedObject public var tab: TabModel
    
    var body: some View {
        NBNavigationStack(path: $navPath) {
            if let nrPost = tab.nrPost {
                ZStack {
                    themes.theme.listBackground
                        .ignoresSafeArea()
                    PostDetailView(nrPost: nrPost, navTitleHidden: true)
                        .debugDimensions("DetailTab.PostDetailView", alignment: .topLeading)
                        .withNavigationDestinations()
                }
            }
            else if let nrLiveEvent = tab.nrLiveEvent {
                ZStack {
                    themes.theme.listBackground
                        .ignoresSafeArea()
                    LiveEventDetail(liveEvent: nrLiveEvent)
                        .withNavigationDestinations()
                }
            }
            else if let nrContact = tab.nrContact {
                ZStack {
                    themes.theme.listBackground
                        .ignoresSafeArea()
                    ProfileView(nrContact:nrContact, tab: tab.profileTab)
                        .withNavigationDestinations()
                }
            }
            else if let notePathId = tab.notePath?.id {
                ZStack {
                    themes.theme.listBackground
                        .ignoresSafeArea()
                    NoteById(id: notePathId, navTitleHidden: true)//.opacity(tm.selected == tab ? 1 : 0)
//                        .environmentObject(dim)
                        .withNavigationDestinations()
                }
                
            }
            else if let naddr1 = tab.naddr1  {
                ZStack {
                    themes.theme.listBackground
                        .ignoresSafeArea()
                    switch naddr1.kind {
                    case 30311:
                        LiveEventByNaddr(naddr1: naddr1.naddr1, navTitleHidden: true, theme: themes.theme)
                            .withNavigationDestinations()
                    default:
                        ArticleByNaddr(naddr1: naddr1.naddr1, navTitleHidden: true, theme: themes.theme)
                            .withNavigationDestinations()
                    }
                }
                
            }
            else if let articleId = tab.articlePath?.id {
                ZStack {
                    themes.theme.listBackground
                        .ignoresSafeArea()
                    ArticleById(id: articleId, navTitleHidden: true, theme: themes.theme)
                        .withNavigationDestinations()
                }
                
            }
            else if let contactPubkey = tab.contactPath?.key {
                ZStack {
                    themes.theme.listBackground
                        .ignoresSafeArea()
                    ProfileByPubkey(pubkey: contactPubkey, tab: tab.contactPath?.tab)//.opacity(tm.selected == tab ? 1 : 0)
                        .withNavigationDestinations()
                }
                
            }
            else if let nrContact = tab.nrContactPath?.nrContact {
                ZStack {
                    themes.theme.listBackground
                        .ignoresSafeArea()
                    ProfileView(nrContact:nrContact, tab: tab.profileTab)
                        .withNavigationDestinations()
                }
                
            }
            else if let galleryVM = tab.galleryVM {
                ZStack {
                    themes.theme.listBackground
                        .ignoresSafeArea()
                    Gallery()
                        .environmentObject(galleryVM)
//                        .withNavigationDestinations()
                }
                
            }
            else {
                EmptyView()
            }
        }
        .nbUseNavigationStack(.never)
        .onReceive(receiveNotification(.navigateTo)) { notification in
            guard tm.selected == tab else { return }
            let destination = notification.object as! NavigationDestination
            let navId = (destination.destination.id as! String)
            // don't navigate to self again
            guard navId != tm.selected?.navId else { return }
            
            guard type(of: destination.destination) != HashtagPath.self else  { return }
            guard type(of: destination.destination) != Nevent1Path.self else  { return }
            guard type(of: destination.destination) != Nprofile1Path.self else  { return }
            guard type(of: destination.destination) != Naddr1Path.self else  { return }
            
            // if we already have a tab of this same destination open, activate it
            if let existingTab = tm.tabs.first(where: { $0.navId == navId }) {
                tm.selected = existingTab
                tm.selected?.suspended = false
                return
            }
            
            // Else just navigate to new destination in this tab
            navPath.append(destination.destination)
        }        
    }
}

struct DetailTab_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer({ pe in pe.loadPosts() }, previewDevice: PreviewDevice(rawValue: "iPad Air (5th generation)")) {
            if let post = PreviewFetcher.fetchNRPost() {
                DetailTab(tab: TabModel(nrPost: post, navId: post.id))
            }
        }
    }
}
