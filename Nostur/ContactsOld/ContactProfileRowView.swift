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
    
    @EnvironmentObject var cm:ConnectionManager
    @Environment(\.managedObjectContext) var viewContext
    @EnvironmentObject var accountState:AccountState
    
    @ObservedObject var contactProfile:ContactProfile
    
    var body: some View {
        //        NavigationLink(value: contactProfile) {}
        
        NavigationLink(value: contactProfile) {
            HStack {
                VStack {
                    ProfilePicView(pubkey: contactProfile.publicKey, contact: contactProfile.contact)
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                    Spacer()
                }
                VStack(alignment: .leading) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(contactProfile.authorName).font(.headline).foregroundColor(.primary)
                                .lineLimit(1)
                            Text("@\(contactProfile.username)").font(.subheadline).foregroundColor(.secondary)
                                .lineLimit(1)
                        }.multilineTextAlignment(.leading)
                        Spacer()
                        Button {
                            if accountState.isFollowing(contactProfile.publicKey) {
                                accountState.unfollow(contactProfile.publicKey)
                            } else {
                                accountState.follow(contactProfile.publicKey, cm: cm)
                            }
                        } label: {
                            FollowButton(isFollowing:accountState.isFollowing(contactProfile.publicKey))
                        }
                    }
                    Text(contactProfile.about).foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
            }
        }
    }
}

struct FollowButton: View {
    @Environment(\.colorScheme) var colorScheme
    var isFollowing: Bool = false
    
    var body: some View {
        
        let whiteColor = colorScheme == .light ? Color.white : Color.black
        let blackColor = colorScheme == .light ? Color.black : Color.white
        
        Text(isFollowing ? "Following" : "Follow")
            .lineLimit(1)
            .frame(width: 65, height: 30)
            .padding(.horizontal, 25)
        //.padding(.vertical, 10)
            .font(.caption.weight(.heavy))
            .foregroundColor(isFollowing ? blackColor : whiteColor)
            .background(isFollowing ? whiteColor : blackColor)
            .cornerRadius(20)
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(.gray, lineWidth: 1)
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
        
        HStack {
            ContactProfileRowInner(contactProfile: contactProfile).padding()
            Divider()
        }
    }
}

struct ContactProfileRowView_Previews: PreviewProvider {
    
    static var previews: some View {
        
        ContactProfileRowViewWrapper()
            .withPreviewEnvironment()
    }
}
