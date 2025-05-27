//
//  BlockListView.swift
//  Nostur
//
//  Created by Fabian Lachman on 04/02/2023.
//

import SwiftUI

struct BlockListScreen: View {
    @EnvironmentObject var themes: Themes
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
                BlockedContactsView()
                
            case "Muted":
                MutedConversationsView()
                //                case "Muted words":
                //                    MutedWordsView()
            default:
                BlockedContactsView()
            }
            Spacer()
        }
        .background(themes.theme.listBackground)
        .navigationTitle(tab)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BlockedContactsView: View {
    @EnvironmentObject private var themes: Themes
    @EnvironmentObject private var la: LoggedInAccount
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt_, order: .reverse)], predicate: NSPredicate(format: "type_ == %@", CloudBlocked.BlockType.contact.rawValue))
    var blockedPubkeys: FetchedResults<CloudBlocked>
    
    @State private var blocksUntil: [String: Date] = [:] // [pubkey: blocked until]
    
    var body: some View {
        List {
            ForEach(blockedPubkeys, id: \.self) { blockedPubkey in
                Box {
                    if let contact = Contact.fetchByPubkey(blockedPubkey.pubkey, context: viewContext) {
                        ProfileRow(withoutFollowButton: true, contact: contact)
//                            .background(themes.theme.background)
                            .overlay(alignment: .topTrailing) {
                                if let until = blocksUntil[blockedPubkey.pubkey] {
                                    Text("blocked until \(until.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding([.top,.trailing], 5)
                                }
                            }
                    }
                    else {
                        HStack(alignment: .top) {
                            PFP(pubkey: blockedPubkey.pubkey)
                            VStack(alignment: .leading) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(blockedPubkey.fixedName).font(.headline).foregroundColor(.primary)
                                            .lineLimit(1)
                                    }
                                    .multilineTextAlignment(.leading)
                                    Spacer()
                                }
                            }
                        }
                        .padding()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            navigateTo(ContactPath(key: blockedPubkey.pubkey), context: "Default")
                        }
                        .background(themes.theme.listBackground)
                        .overlay(alignment: .topTrailing) {
                            if let until = blocksUntil[blockedPubkey.pubkey] {
                                Text("blocked until \(until.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding([.top,.trailing], 5)
                            }
                        }
                    }
                }
                .listRowSeparator(.hidden)
//                .listRowBackground(themes.theme.listBackground)
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
//                .padding(.bottom, GUTTER)
            }
            .onDelete { indexSet in
                unblock(section: Array(blockedPubkeys), offsets: indexSet)
            }
        }
        .toolbar {
            EditButton()
        }
        .environment(\.defaultMinListRowHeight, 50)
        .listStyle(.plain)
        .task {
            CloudTask.fetchAll(byType: .blockUntil)
                .forEach { task in
                    blocksUntil[task.value] = task.date
                }
            
            removeDuplicates()
        }
    }
    
    private func removeDuplicates() {
        var uniqueBlockedPubkeys = Set<String>()
        let sortedBlockedPubkeys = blockedPubkeys.sorted {
            ($0.createdAt_ as Date?) ?? Date.distantPast > ($1.createdAt_ as Date?) ?? Date.distantPast
        }
        
        let duplicates = sortedBlockedPubkeys
            .filter { blockedPubkey in
                guard let pubkey = blockedPubkey.pubkey_ else { return false }
                return !uniqueBlockedPubkeys.insert(pubkey).inserted
            }
        
        L.cloud.debug("Deleting: \(duplicates.count) duplicate blocked contacts")
        duplicates.forEach {
            DataProvider.shared().viewContext.delete($0)
        }
        if !duplicates.isEmpty {
            DataProvider.shared().save()
        }
    }
    
    private func unblock(section: [CloudBlocked], offsets: IndexSet) {
        for index in offsets {
            let block = section[index]
            viewContext.delete(block)
            AppState.shared.bgAppState.blockedPubkeys.remove(block.pubkey)
        }
        viewContextSave()
        sendNotification(.blockListUpdated, AppState.shared.bgAppState.blockedPubkeys)
    }
}

struct MutedConversationsView: View {
    @EnvironmentObject var themes: Themes
    @ObservedObject var settings:SettingsStore = .shared
    
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdAt_, order: .reverse)], predicate: NSPredicate(format: "type_ == %@", CloudBlocked.BlockType.post.rawValue))
    var mutedRootIds: FetchedResults<CloudBlocked>
    
    var body: some View {
        List {
            ForEach(mutedRootIds, id: \.self) { mutedRootId in
                Box {
                    if let event = Event.fetchEvent(id: mutedRootId.eventId, context: viewContext) {
                        HStack(spacing: 10) {
                            PFP(pubkey: event.pubkey, contact: event.contact, size: 25)
                                .onTapGesture {
                                    navigateTo(ContactPath(key: event.pubkey), context: "Default")
                                }
                            MinimalNoteTextRenderViewText(plainText: event.plainText, lineLimit: 1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { navigateTo(NotePath(id: event.id), context: "Default") }
                        }
                    }
                    else {
                        HStack(spacing: 10) {
                            PFP(pubkey: mutedRootId.eventId, size: 25)
                            NRTextDynamic("Can't find event id: \(note1(mutedRootId.eventId) ?? "?")")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { navigateTo(NotePath(id: mutedRootId.eventId), context: "Default") }
                        }
                    }
                }
                .id(mutedRootId.eventId)
                .listRowSeparator(.hidden)
                .listRowBackground(themes.theme.listBackground)
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                .padding(.bottom, GUTTER)
            }
            .onDelete { indexSet in
                unmute(section: Array(mutedRootIds), offsets: indexSet)
            }
        }
        .toolbar {
            EditButton()
        }
        .environment(\.defaultMinListRowHeight, 50)
        .listStyle(.plain)
        .onAppear {
            removeDuplicates()
        }
    }
    
    private func unmute(section: [CloudBlocked], offsets: IndexSet) {
        for index in offsets {
            let mute = section[index]
            viewContext.delete(mute)
            AppState.shared.bgAppState.mutedRootIds.remove(mute.eventId)
        }
        viewContextSave()
        sendNotification(.muteListUpdated, AppState.shared.bgAppState.mutedRootIds)
    }
    
    private func removeDuplicates() {
        var uniqueMutedRootIds = Set<String>()
        let sortedMutedRootIds = mutedRootIds.sorted {
            ($0.createdAt_ as Date?) ?? Date.distantPast > ($1.createdAt_ as Date?) ?? Date.distantPast
        }
        
        let duplicates = sortedMutedRootIds
            .filter { mutedRootId in
                guard let eventId = mutedRootId.eventId_ else { return false }
                return !uniqueMutedRootIds.insert(eventId).inserted
            }
        
        L.cloud.debug("Deleting: \(duplicates.count) duplicate muted conversations")
        duplicates.forEach {
            DataProvider.shared().viewContext.delete($0)
        }
        if !duplicates.isEmpty {
            DataProvider.shared().save()
        }
    }
}

struct BlockListView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            VStack {
                BlockListScreen()
            }
        }
    }
}
