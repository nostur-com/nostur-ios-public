//
//  ProfileToolbar.swift
//  Nostur
//
//  Created by Fabian Lachman on 24/02/2025.
//

import SwiftUI
import NavigationBackport

struct ProfileToolbar: View {
    @Environment(\.theme) private var theme
    public let pubkey: String
    public let nrContact: NRContact
    @ObservedObject var scrollPosition: ScrollPosition
    @Binding var editingAccount: CloudAccount?
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 2) {
                PFP(pubkey: nrContact.pubkey, nrContact: nrContact, size: 25)
                    .overlay(
                        Circle()
                            .strokeBorder(theme.listBackground, lineWidth: 1)
                    )
                Text("\(nrContact.anyName) ").font(.headline)
                
                Spacer()
                
                if pubkey == AccountsState.shared.activeAccountPublicKey {
                    Button {
                        guard let account = account() else { return }
                        guard isFullAccount(account) else { showReadOnlyMessage(); return }
                        editingAccount = account
                    } label: {
                        Text("Edit profile", comment: "Button to edit own profile")
                    }
                    .buttonStyle(NosturButton())
                    .layoutPriority(2)
                    //                                    .offset(y: 123 + (max(-123,toolbarGEO.frame(in:.global).minY)))
                }
                else {
                    FollowButton(pubkey: nrContact.pubkey)
                        .layoutPriority(2)
                    //                                    .offset(y: 123 + (max(-123,toolbarGEO.frame(in:.global).minY)))
                }
                
            }
            
        }
        .offset(y: max(2, scrollPosition.position.y))
        .frame(height: 40)
        .clipped()
    }
}
