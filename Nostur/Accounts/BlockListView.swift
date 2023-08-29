//
//  BlockListView.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/02/2023.
//

import SwiftUI

struct BlockListView: View {
    @EnvironmentObject var theme: Theme
    @State var tab = "Blocked"
    
    var body: some View {
        VStack {
            HStack {
                TabButton(action: {
                    tab = "Blocked"
                }, title: String(localized: "Blocked", comment: "Title of tab where Blocked users are listed"), selected: tab == "Blocked")
                
                TabButton(action: {
                    tab = "Muted"
                }, title: String(localized:"Muted conversations", comment:"Title of tab where Muted conversations are listed"), selected: tab == "Muted")
                //                TabButton(action: {
                //                        tab = "Muted words"
                //                }, title: "Muted words", selected: tab == "Muted words")
            }
            switch tab {
            case "Blocked":
                BlockedAccounts()
                Text("Swipe to unblock/unmute", comment: "Informational text")
            case "Muted":
                MutedConversations()
                Text("Swipe to unblock/unmute", comment: "Informational text")
                //                case "Muted words":
                //                    MutedWordsView()
            default:
                BlockedAccounts()
            }
            Spacer()
        }
        .background(theme.listBackground)
        .navigationTitle(tab)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BlockedAccounts:View {
    @EnvironmentObject var theme: Theme
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(value: false))
    var blockedContacts:FetchedResults<Contact>
    
    var body: some View {
        if let account = ns.account {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(blockedContacts.sorted(by: { $0.authorName < $1.authorName })) { contact in
                        ProfileRow(withoutFollowButton: true, contact: contact)
                            .background(theme.background)
                            .onSwipe(tint: .green, label: "Unblock", icon: "figure.2.arms.open") {
                                ns.objectWillChange.send()
                                account.blockedPubkeys_.removeAll(where: { $0 == contact.pubkey })
                                DataProvider.shared().save()
                                sendNotification(.blockListUpdated, account.blockedPubkeys_)
                            }
                    }
                }
            }
            .onAppear {
                if let account = ns.account {
                    blockedContacts.nsPredicate = NSPredicate(format: "pubkey IN %@", account.blockedPubkeys_)
                }
            }
            .onChange(of: ns.account!.blockedPubkeys_) { newValue in
                blockedContacts.nsPredicate = NSPredicate(format: "pubkey IN %@", newValue)
            }
            .onReceive(receiveNotification(.blockListUpdated)) { notification in
                let newBlockList = notification.object as! [String]
                blockedContacts.nsPredicate = NSPredicate(format: "pubkey IN %@", newBlockList)
            }
        }
        else {
            Text("Please choose account first")
        }
    }
}

struct MutedConversations: View {
    @EnvironmentObject var theme: Theme
    @ObservedObject var settings:SettingsStore = .shared
    @EnvironmentObject var ns:NosturState
    @StateObject var fl = FastLoader()
    @State var didLoad = false
    @State var backlog = Backlog()
    
    var body: some View {
        Group {
            if let account = ns.account {
                LazyVStack(spacing: 10) {
                    ForEach(fl.nrPosts) { nrPost in
                        Box {
                            HStack(spacing: 10) {
                                PFP(pubkey: nrPost.pubkey, nrContact: nrPost.contact, size: 25)
                                    .onTapGesture {
                                        navigateTo(ContactPath(key: nrPost.pubkey))
                                    }
                                MinimalNoteTextRenderView(nrPost: nrPost, lineLimit: 1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture { navigateTo(nrPost) }
                            }
                        }
                        .id(nrPost.id)
                        .onSwipe(tint: Color.green, label: "Unmute", icon: "speaker.wave.1") {
                            ns.objectWillChange.send()
                            account.mutedRootIds_.removeAll(where: { $0 == nrPost.id })
                            fl.nrPosts = fl.nrPosts.filter { $0.id != nrPost.id }
                            DataProvider.shared().save()
                        }
                    }
                    Spacer()
                }
                //                .background(Color("ListBackground"))
                .onChange(of: account.mutedRootIds_) { newValue in
                    fl.reset()
                    fl.predicate = NSPredicate(format: "id IN %@", newValue)
                    fl.loadMore(1000, includeSpam: true)
                }
            }
        }
        .onAppear {
            guard let account = ns.account else { return }
            guard !didLoad else { return }
            didLoad = true
            fl.predicate = NSPredicate(format: "id IN %@", account.mutedRootIds_)
            fl.sortDescriptors = [NSSortDescriptor(keyPath:\Event.created_at, ascending: false)]
            fl.transformer = { event in
                NRPost(event: event, withReplyTo: false, withParents: false, withReplies: false, plainText: true)
            }
            fl.loadMore(1000, includeSpam: true)
            
        }
        
    }
}

struct BlockListView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            VStack {
                BlockListView()
            }
        }
    }
}
