//
//  AccountFollowingList.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/02/2023.
//
import SwiftUI
import CoreData

struct AccountFollowingList: View {
    var account:Account
    var sp:SocketPool = .shared
    @Environment(\.managedObjectContext) var viewContext
    @State var searchText = ""
    
    var body: some View {
        ScrollView {
            VStack {
                ForEach(Array(account.follows?.filter({ contact in
                    if (searchText == "") { return true }
                    if contact.authorName.contains(searchText) {
                        return true
                    }
                    if contact.username.contains(searchText) {
                        return true
                    }
                    if contact.about != nil && contact.about!.contains(searchText) {
                        return true
                    }
                    return false
                }) ?? [])) { contact in
                    ProfileRow(contact: contact)
                    Divider()
                }
            }
        }
        .padding(10)
        .searchable(text: $searchText)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button {
                    do {
                        try publishFollowersList(account: account, sp: sp, context: viewContext)
                    }
                    catch {
                        print("Could not publish followers list (kind=3)")
                        print(error)
                    }
                    
                } label: { Text("Publish your followers list") }
                    .buttonStyle(.borderedProminent)
                Spacer()
            }.background(.regularMaterial)
        }
    }
    
    // TODO: MOVE TO Event Publisher class
    func publishFollowersList(account:Account, sp:SocketPool, context:NSManagedObjectContext) throws {
        guard account.privateKey != nil else {
            throw "Account has no private key"
        }
        
        // create nostr contact list event
        var nEvent = NEvent(content: "")
        nEvent.publicKey = account.publicKey!
        nEvent.kind = .custom(3)
        nEvent.tags = (Array(account.follows ?? Set<Contact>())).map({ contact in
            let tag = NEventTag.pubKey(publicKey: contact.pubkey!)
            return tag
        })
        
        if (account.privateKey != nil) {
            let keys = NKeys(privateKeyHex: account.privateKey!)
            
            do {
                nEvent = try nEvent.sign(keys)
                
                print(nEvent.eventJson())
                print(nEvent.wrappedEventJson())
                
                _ = Event.saveEvent(event: nEvent, context: context)
                try context.save()
                
                // broadcast to relays
                let message = ClientMessage(type: .EVENT, message: nEvent.wrappedEventJson())
                sp.sendMessage(message)
            }
            catch {
                print("🔴🔴🔴🔴 Could not sign/save/broadcast event 🔴🔴🔴🔴")
            }
        }
    }
}

struct AccountFollowingList_Previews: PreviewProvider {
    
    static var previews: some View {
        let account = PreviewFetcher.fetchAccount()
        AccountFollowingList(account: account!)
            .withPreviewEnvironment()
    }
}
