//
//  PrivateNotesView.swift
//  Nostur
//
//  Created by Fabian Lachman on 13/03/2023.
//

import SwiftUI

import SwiftUI

struct PrivateNotesContainer: View {
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var nav:NavigationModel
    
    init() {
        print("🧨🧨🧨🧨🧨 INIT PRIVATE NOTES CONTAINER 🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨")
    }
    
    var body: some View {
        let _ = Self._printChanges()
        VStack {
            if (ns.account != nil) {
                PrivateNotesView(account: ns.account!)
            }
            else {
                Text("Select account account first")
            }
        }
    }
}

struct PrivateNotesView: View {
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var ns:NosturState
    
    let account: Account
    
    @FetchRequest(sortDescriptors: [])
    var notes: FetchedResults<PrivateNote>
    
    @State var selectedAccount:Account? = nil
    
    init(account:Account) {
        print("🧨🧨🧨🧨🧨 INIT PRIVATE NOTES VIEW 🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨")
        self.account = account
        self.selectedAccount = account
        _notes = FetchRequest(
            sortDescriptors: [SortDescriptor(\PrivateNote.updatedAt, order: .reverse)],
            predicate: NSPredicate(value: true)
        )
    }
    
    var body: some View {
        let _ = Self._printChanges()
        VStack {
            HStack {
                Spacer()
                Menu {
                    Button {
                        selectedAccount = nil
                    } label: {
                        HStack {
                            Text("All accounts")
                            Spacer()
                        }
                    }
                    ForEach(ns.accounts) { account in
                        Button {
                            selectedAccount = account
                        } label: {
                            HStack {
                                Text("@\(account.name)")
                                Spacer()
                            }
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        ZStack {
                            if (selectedAccount != nil) {
                                ProfilePicView(pubkey: selectedAccount!.publicKey, account: selectedAccount, size: 30)
                            }
                            else {
                                ForEach(ns.accounts.indices, id:\.self) { index in
                                    ProfilePicView(pubkey: ns.accounts[index].publicKey, account: ns.accounts[index], size: 30)
                                        .offset(x: -CGFloat(index*10))
                                    
                                }
                            }
                        }
                    }
                    .frame(width: 150)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.visible)
            }
            .padding(.horizontal)
            List {
                ForEach(notes) { note in
                    PrivateNoteRow(note:note)
                        .listRowInsets(EdgeInsets())
                }
                .onDelete(perform: deleteItems)
            }
            .listStyle(.plain)
            Spacer()
        }
        .navigationTitle("Private Notes")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(true)
        .padding()
        .onChange(of: selectedAccount) { newValue in
            if (newValue != nil) {
                notes.nsPredicate = NSPredicate(format: "by == %@", newValue!)
            }
            else {
                notes.nsPredicate = NSPredicate(value: true)
            }
        }
    }
    
    private func deleteItems(offsets: IndexSet) {
        withAnimation {
//            ns.objectWillChange.send()
            offsets.map { notes[$0] }.forEach(viewContext.delete)
            do { try viewContext.save() } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

struct PrivateNoteRow: View {
    @ObservedObject var note: PrivateNote
    @EnvironmentObject var nav:NavigationModel
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment:.top) {
                Text(note.content_ == "" ? "(Empty note)" : note.content_)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let post = note.post {
                            sendNotification(.editingPrivateNoteOnPost, post.id)
                        }
                        else if let contact = note.contact {
                            sendNotification(.editingPrivateNoteOnContact, contact.pubkey)
                        }
                    }
                Spacer()
                Text(note.ago)
                    .frame(alignment: .trailing)
                    .foregroundColor(.secondary)
                    .padding(.trailing, 5)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 10)
            if let vPost = note.post?.toVPost() {
                HStack {
                    PFP(pubkey: vPost.pubkey, pictureUrl: vPost.vContact?.pictureUrl, size: 25)
                        .onTapGesture {
                            nav.navigateTo(ContactPath(key: vPost.pubkey))
                        }
                    MinimalNoteTextRenderView(vPost: vPost, lineLimit: 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture { nav.navigateTo(vPost) }
                }
            }
            else if let contact = note.contact {
                HStack {
                    ProfilePicView(pubkey: contact.pubkey, contact: contact, size: 25)
                    Text(contact.authorName) // Name
                        .foregroundColor(.secondary)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .layoutPriority(2)
                    
                    if (contact.nip05veried) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.blue)
                            .layoutPriority(3)
                    }
                    
                    Text("@\(contact.username)").layoutPriority(1)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    Text(contact.about ?? "").lineLimit(1)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    nav.navigateTo(ContactPath(key: contact.pubkey))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        
    }
}

struct PrivateNotesView_Previews: PreviewProvider {
    static var previews: some View {
        PrivateNotesContainer()
            .withPreviewEnvironment()
    }
}
