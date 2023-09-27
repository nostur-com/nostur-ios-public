//
//  BookmarksView.swift
//  Nostur
//
//  Created by Fabian Lachman on 25/01/2023.
//

import SwiftUI

struct BookmarksView: View {
    @EnvironmentObject private var theme:Theme
    @EnvironmentObject private var ns:NRState
    @AppStorage("selected_bookmarkssubtab") private var selectedSubTab = "Bookmarks"

    private let account: Account
    @Binding private var navPath:NavigationPath
    @State private var vBookmarks:[NRPost] = []

//    private var accounts:[Account] {
//        ns.accounts.filter { $0.privateKey != nil }
//    }

    @ObservedObject private var settings:SettingsStore = .shared
//    @State private var selectedAccount:Account? = nil
    @Namespace private var top

    init(account:Account, navPath:Binding<NavigationPath>) {
        _navPath = navPath
        self.account = account
//        self.selectedAccount = account
    }

    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 1).id(top)
                if !vBookmarks.isEmpty {
                    LazyVStack(spacing: 10) {
                        ForEach(vBookmarks) { vBookmark in
                            Box(nrPost: vBookmark) {
                                PostRowDeletable(nrPost: vBookmark, missingReplyTo: true, fullWidth: settings.fullWidthImages)
                            }
    //                        .frame(maxHeight: DIMENSIONS.POST_MAX_ROW_HEIGHT)
    //                        .fixedSize(horizontal: false, vertical: true)
                            .id(vBookmark.id)
                            .onDelete {
                                withAnimation {
                                    vBookmarks = vBookmarks.filter { $0.id != vBookmark.id }
                                }
                                
                                bg().perform {
                                    vBookmark.event.bookmarkedBy = []
                                    DataProvider.shared().bgSave()
                                }
                            }
                        }
                        Spacer()
                    }
                    .background(theme.listBackground)
                }
                else {
                    Text("When you bookmark a post it will show up here.")
                        .hCentered()
                        .padding(.top, 40)
                }
            }
            .onReceive(receiveNotification(.didTapTab)) { notification in
                guard selectedSubTab == "Bookmarks" else { return }
                guard let tabName = notification.object as? String, tabName == "Bookmarks" else { return }
                if navPath.count == 0 {
                    withAnimation {
                        proxy.scrollTo(top)
                    }
                }
            }
        }
//        .overlay(alignment:.topTrailing) {
//            AccountSwitcher(accounts: accounts, selectedAccount: $selectedAccount)
//                .padding(.horizontal)
//        }
        .onReceive(receiveNotification(.postAction)) { notification in
            let action = notification.object as! PostActionNotification
            if (action.type == .bookmark  && !action.bookmarked) {
                withAnimation {
                    vBookmarks = vBookmarks.filter { $0.id != action.eventId }
                }
            }
            else if action.type == .bookmark {
                self.loadBookmarks()
            }
        }
        .navigationTitle(String(localized:"Bookmarks", comment:"Navigation title for Bookmarks screen"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
//        .onChange(of: selectedAccount) { account in
//            self.loadBookmarks(forAccount: account)
//        }
        .task {
            self.loadBookmarks()
        }
        .simultaneousGesture(
               DragGesture().onChanged({
                   if 0 < $0.translation.height {
                       sendNotification(.scrollingUp)
                   }
                   else if 0 > $0.translation.height {
                       sendNotification(.scrollingDown)
                   }
               }))
    }
    
    private func loadBookmarks(forAccount account: Account? = nil) {
        let fr = Event.fetchRequest()
        if let account {
            fr.predicate = NSPredicate(format: "%@ IN bookmarkedBy", account)
        }
        else {
            fr.predicate = NSPredicate(format: "bookmarkedBy.@count > 0")
        }
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)]
        
        let ctx = DataProvider.shared().bg
        ctx.perform {
            if let bookmarks = try? ctx.fetch(fr) {
                self.vBookmarks = bookmarks.map { NRPost(event: $0) }
            }
        }
    }
}

#Preview("Bookmarks") {
    PreviewContainer({ pe in
        pe.loadPosts()
        pe.loadBookmarks()
    }) {
        VStack {
            if let account = NRState.shared.loggedInAccount?.account {
                BookmarksView(account: account, navPath: .constant(NavigationPath()))
            }
        }
    }
}
