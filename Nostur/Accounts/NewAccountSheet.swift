//
//  NewAccountSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/02/2023.
//

import SwiftUI
import secp256k1
import Foundation

struct NewAccountSheet: View {
    @EnvironmentObject private var themes: Themes
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var name = ""
    @State private var about = ""
    
    private enum FocusedField {
        case name
    }
    
    @FocusState private var focusedField: FocusedField?
    
    private var grayBackground: Color = Color.white.opacity(0.3)
    
    var body: some View {
            VStack {
                TextField("", text: $name, prompt: Text("Name", comment:"Label of Name text field on Create new account screen").foregroundColor(Color.black))
                    .disableAutocorrection(true)
                    .padding()
                    .background(grayBackground)
                    .cornerRadius(5.0)
                    .padding(.bottom, 20)
                    .focused($focusedField, equals: .name)
                TextField("", text: $about, prompt: Text("Something about yourself (bio)", comment:"Label of bio/about text field on Create new account screen").foregroundColor(Color.black))
                    .lineLimit(5)
                    .padding()
                    .background(grayBackground)
                    .cornerRadius(5.0)
                    .padding(.bottom, 20)
                    
                Button {
                    createAccount()
                } label: {
                    Text("Create")
                        .frame(maxWidth: .infinity)
                }
                .fontWeightBold()
                .tint(.black.opacity(0.65))
                .buttonStyle(.borderedProminent)
                .clipShape(Capsule())
                
                if (AccountsState.shared.accounts.first(where: { $0.publicKey == GUEST_ACCOUNT_PUBKEY}) == nil)  {
                    NavigationLink {
                        TryGuestAccountSheet()
                    } label: {
                        Text("Or, skip and try as guest first", comment: "Button to skip creating account and login as guest")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 20)
                }
                
            }
            .frame(maxWidth: 300)
            .controlSize(.large)
            .buttonStyle(.bordered)
            .onAppear { focusedField = .name }
            .navigationTitle(String(localized: "Create new account", comment: "Navigation title of create new account screen"))
            .navigationBarTitleDisplayMode(.inline)
            .wowBackground()
            .foregroundColor(Color.white)
    }
    
    func createAccount() {
        guard let newAccount = AccountManager.shared.generateAccount(name: name, about: about, context: viewContext),
              let newKind0EventSigned = AccountManager.createUserMetadataEvent(account: newAccount),
              let newKind10002Eventsigned = AccountManager.createRelayListMetadataEvent(account: newAccount)
        else { L.og.error("🔴🔴 could not createAccount()"); return }
        
        let bgContext = bg()
        bgContext.perform {
            // create profile kind:0
            _ = Event.saveEvent(event: newKind0EventSigned, context: bgContext)
            Contact.saveOrUpdateContact(event: newKind0EventSigned, context: bgContext)
            
            // create relays kind:10002
            _ = Event.saveEvent(event: newKind10002Eventsigned, context: bgContext)
            
            DataProvider.shared().bgSave()
            
            // Publish kind:0 and kind:10002
            Unpublisher.shared.publishNow(newKind0EventSigned)
            Unpublisher.shared.publishNow(newKind10002Eventsigned)
        }
        dismiss()
        AccountsState.shared.changeAccount(newAccount)
    }
}

#Preview {
    PreviewContainer {
        NewAccountSheet()
    }
}
