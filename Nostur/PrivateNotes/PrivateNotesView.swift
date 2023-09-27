//
//  PrivateNotesView.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/03/2023.
//

import SwiftUI
import CoreData

struct PrivateNoteInfo: Identifiable {
    var id:NSManagedObjectID { note.objectID }
    var note:PrivateNote // Main context
    var nrPost:NRPost? // Created in BG context
    var event:Event? // needed to know if we create should NRPost in bg. because we cannot access note.event, so we set event in the maincontext, which we can then use in bg.
}

struct PrivateNotesView: View {
    @EnvironmentObject private var ns:NRState
    @EnvironmentObject private var theme:Theme
    @AppStorage("selected_bookmarkssubtab") private var selectedSubTab = "Private Notes"
    @Environment(\.managedObjectContext) private var viewContext
    
    private let account: Account
    @Binding private var navPath:NavigationPath
    
    @State private var privateNotes = [PrivateNoteInfo]()
//    @State private var selectedAccount:Account? = nil
    @Namespace private var top

    init(account:Account, navPath:Binding<NavigationPath>) {
        _navPath = navPath
        self.account = account
//        self.selectedAccount = account
    }
//
//    private var accounts:[Account] {
//        ns.accounts.filter { $0.privateKey != nil }
//    }
    
    var body: some View {
        #if DEBUG
        let _ = Self._printChanges()
        #endif
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 1).id(top)
                if !privateNotes.isEmpty {
                    LazyVStack(spacing: 10) {
                        ForEach(privateNotes) { pnInfo in
                            PrivateNoteRow(note: pnInfo.note, nrPost: pnInfo.nrPost)
                                .background(theme.background)
                                .onDelete {
                                    withAnimation {
                                        privateNotes = privateNotes.filter { $0.note.id != pnInfo.note.id }
                                    }
                                    viewContext.delete(pnInfo.note)
                                    DataProvider.shared().save()
                                }
                        }
                        Spacer()
                    }
                }
                else {
                    Text("When you add a private note to a post or profile it will show up here.", comment: "Message shown when private note screen is empty")
                        .hCentered()
                        .padding(.top, 40)
                }
            }
            .onReceive(receiveNotification(.didTapTab)) { notification in
                guard selectedSubTab == "Private Notes" else { return }
                guard let tabName = notification.object as? String, tabName == "Bookmarks" else { return }
                if navPath.count == 0 {
                    withAnimation {
                        proxy.scrollTo(top)
                    }
                }
            }
        }
        .background(theme.listBackground)
//        .overlay(alignment:.topTrailing) {
//            AccountSwitcher(accounts: accounts, selectedAccount: $selectedAccount)
//                .padding(.horizontal)
//        }
        .navigationTitle(String(localized:"Private Notes", comment:"Navigation title for Private Notes screen"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
//        .padding()
        .onReceive(receiveNotification(.postAction)) { notification in
            let action = notification.object as! PostActionNotification
            if (action.type == .privateNote  && !action.hasPrivateNote) {
                withAnimation {
                    privateNotes = privateNotes.filter {
                        $0.note.post == nil ||
                        $0.note.post!.id != action.eventId
                    }
                }
            }
            else if action.type == .privateNote {
                self.loadPrivateNotes()
            }
        }
//        .onChange(of: selectedAccount) { newValue in
//            loadPrivateNotes()
//        }
        .task {
            loadPrivateNotes()
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
    
    private func loadPrivateNotes(forAccount account: Account? = nil) {
        let fr = PrivateNote.fetchRequest()
        if let account {
            fr.predicate = NSPredicate(format: "by == %@", account)
        }
        else {
            fr.predicate = NSPredicate(value: true)
        }
        fr.sortDescriptors = [NSSortDescriptor(keyPath: \PrivateNote.createdAt, ascending: false)]
        
        
        if let privateNotes = try? viewContext.fetch(fr) {
            let privateNotesWithoutNRPost = privateNotes.map {
                PrivateNoteInfo(note: $0, event: $0.post)
            }
        
            DataProvider.shared().bg.perform {
                let privateNotesComplete = privateNotesWithoutNRPost.map { pnInfo in
                    return PrivateNoteInfo(
                        note: pnInfo.note,
                        nrPost: pnInfo.event != nil ? NRPost(event: pnInfo.event!.toBG()!) : nil,
                        event: pnInfo.event
                    )
                }
                DispatchQueue.main.async {
                    self.privateNotes = privateNotesComplete
                }
            }
        }
    }
}

#Preview("Private Notes") {
    PreviewContainer({ pe in
        pe.loadContacts()
        pe.loadPosts()
        pe.loadPrivateNotes()
    }) {
        VStack {
            if let account = NRState.shared.loggedInAccount?.account {
                PrivateNotesView(account: account, navPath: .constant(NavigationPath()))
            }
        }
    }
}
