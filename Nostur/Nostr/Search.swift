//
//  Search.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/02/2023.
//

import SwiftUI
import Combine

struct Search: View {
    
    @StateObject var debounceObject = DebounceObject()

    var sp:SocketPool = .shared
    
    @FetchRequest(
        entity: Event.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
        predicate: NSPredicate(value: false),
        animation: .none)
    var events:FetchedResults<Event>
    
    @FetchRequest(
        entity: Contact.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
        predicate: NSPredicate(value: false),
        animation: .none)
    var contacts:FetchedResults<Contact>
    
    @State var searching = false
    
    var body: some View {
        let _ = Self._printChanges()
        ScrollView {
            if (contacts.count == 0 && events.count == 0 && searching) {
                ProgressView()
            }
            ForEach(contacts) { contact in
                ProfileRow(contact: contact)
                Divider()
            }
            ForEach(events) { event in
                NoteRowView(event: event)
                Divider()
            }
        }
        .padding(10)
        .searchable(text: $debounceObject.text, placement: .navigationBarDrawer(displayMode: .always))
        .onChange(of: debounceObject.debouncedText) { searchString in
            
            let searchTrimmed = searchString.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // try npub
            if (searchTrimmed.prefix(5) == "npub1") {
                do {
                    searching = true
                    let key = try NIP19(displayString: searchTrimmed)
                    contacts.nsPredicate = NSPredicate(format: "pubkey = %@", key.hexString)
                    events.nsPredicate = NSPredicate(value: false)
                    sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: key.hexString)))
                }
                catch {
                    print("npub1 search fail \(error)")
                    searching = false
                }
            }
            
            // try note1
            else if (searchTrimmed.prefix(5) == "note1") {
                do {
                    searching = true
                    let key = try NIP19(displayString: searchTrimmed)
                    events.nsPredicate = NSPredicate(format: "id = %@", key.hexString)
                    contacts.nsPredicate = NSPredicate(value: false)
                    sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: key.hexString)))
                }
                catch {
                    print("note1 search fail \(error)")
                    searching = false
                }
            }
            // else try hex id or pubkey
            else if (searchTrimmed.count == 64) {
                searching = true
                events.nsPredicate = NSPredicate(format: "id = %@", searchTrimmed)
                contacts.nsPredicate = NSPredicate(format: "pubkey = %@", searchTrimmed)
                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getEvent(id: searchTrimmed)))
                sp.sendMessage(ClientMessage(type: .REQ, message: RequestMessage.getUserMetadata(pubkey: searchTrimmed)))
                Task {
                    try? await Task.sleep(nanoseconds: 5_500_000_000)
                    searching = false
                }
            }
            // search in names/usernames
            else {
                searching = false
                events.nsPredicate = NSPredicate(format: "kind == 1 AND content CONTAINS[cd] %@", searchTrimmed)
                contacts.nsPredicate = NSPredicate(format: "name CONTAINS[cd] %@ OR display_name CONTAINS[cd] %@", searchTrimmed, searchTrimmed)
            }
        }
    }
}

public final class DebounceObject: ObservableObject {
    @Published var text: String = ""
    @Published var debouncedText: String = ""
    private var bag = Set<AnyCancellable>()

    public init(dueTime: TimeInterval = 0.4) {
        $text
            .removeDuplicates()
            .debounce(for: .seconds(dueTime), scheduler: DispatchQueue.main)
            .sink(receiveValue: { [weak self] value in
                self?.debouncedText = value
            })
            .store(in: &bag)
    }
}

struct Search_Previews: PreviewProvider {
    static var previews: some View {
        Search()
            .withPreviewEnvironment()
    }
}
