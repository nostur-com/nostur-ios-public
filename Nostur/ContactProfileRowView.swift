//
//  ContactProfileRowView.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/01/2023.
//

import SwiftUI

struct ContactProfileRowView: View {
    
    //    @Environment(\.managedObjectContext) var viewContext
    
    var pubkey:String
    
    @FetchRequest
    var contacts:FetchedResults<Contact>
    
    @FetchRequest
    var metaDataEvents: FetchedResults<Event>
    
//    @FetchRequest
//    var contactListEvents: FetchedResults<Event>
    
    init(pubkey:String) {
        self.pubkey = pubkey
        _contacts = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
            predicate: NSPredicate(format: "pubkey == %@", pubkey)
        )
        
        _metaDataEvents = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
            predicate: NSPredicate(format: "pubkey == %@ AND kind == 0", pubkey)
        )
        
//        _contactListEvents = FetchRequest(
//            sortDescriptors: [NSSortDescriptor(keyPath: \Event.created_at, ascending: false)],
//            predicate: NSPredicate(format: "pubkey == %@ AND kind == 3", pubkey)
//        )
    }
    
    var body: some View {
        if (contacts.first != nil) {
//            if (contactListEvents.first != nil) {
//                let contactProfile = ContactProfile(contact: contacts.first!, clEvent: contactListEvents.first!)
//                ContactProfileRowInner(contactProfile: contactProfile)
//            }
//            else {
                let contactProfile = ContactProfile(contact: contacts.first!)
                ContactProfileRowInner(contactProfile: contactProfile)
//            }
            
        }
        else {
            Text("...")
        }
    }
}

struct ContactProfileRowInner: View {
    
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var accountState:AccountState
    
    var contactProfile:ContactProfile
    
    var body: some View {
        
        HStack(alignment: .top) {
            NavigationLink(value: contactProfile) {
                HStack(alignment: .top) {
                    ProfilePicView(pubkey: contactProfile.publicKey, contact: contactProfile.contact)
                        .frame(width: 50, height: 50)
                    VStack(alignment: .leading) {
                        Text(contactProfile.authorName).font(.headline).foregroundColor(.primary)
                        Text("@\(contactProfile.username)").font(.subheadline).foregroundColor(.secondary)
                        Text(contactProfile.about).foregroundColor(.primary)
                    }.multilineTextAlignment(.leading)
                    Spacer()
                }
            }
            
            Button {
                if accountState.isFollowing(contactProfile.publicKey) {
                    accountState.unfollow(contactProfile.publicKey)
                } else {
                    accountState.follow(contactProfile.publicKey)
                }
            } label: {
                Text(accountState.isFollowing(contactProfile.publicKey) ? "Following" : "Follow")
                    .frame(height: 30)
                    .padding(.horizontal, 25)
                //.padding(.vertical, 10)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.primary)
                    .background(.clear)
                    .cornerRadius(20)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.primary, lineWidth: 1)
                    }
            }
        }
        
    }
}


// FOR PREVIEW
struct ContactProfileRowViewWrapper: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Contact.updated_at, ascending: false)],
        predicate: NSPredicate(format: "pubkey == %@", "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"),
        animation: .none)
    var contacts:FetchedResults<Contact>
    
    @FetchRequest(fetchRequest:Event.setMetaDataEvents(byAuthorPubkey: "5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0"))
    var metaDataEvents: FetchedResults<Event>
    
    var body: some View {
        let contactProfile = ContactProfile(contact: contacts.first!)
        
        ContactProfileRowInner(contactProfile: contactProfile)
    }
}

struct ContactProfileRowView_Previews: PreviewProvider {
    
    static var previewUserDefaults: UserDefaults = {
        let d = UserDefaults(suiteName: "preview_user_defaults")!
        
        d.set("5e9c1fb5fe7e1695833539636a30d678e54e3e4e1214ff3d3f71501bbfd62cd0", forKey: "activeAccountPublicKey")
        
        return d
    }()
    
    static var previews: some View {
        
        let accountState = AccountState(viewContext: PersistenceController.preview.container.viewContext)
        
        ContactProfileRowViewWrapper()
            .defaultAppStorage(previewUserDefaults)
            .environment(\.managedObjectContext,
                          PersistenceController.preview.container.viewContext)
            .environmentObject(accountState)
    }
}
