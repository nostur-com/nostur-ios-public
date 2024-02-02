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
    @EnvironmentObject private var themes:Themes
    @EnvironmentObject private var ns:NRState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var name = ""
    @State private var about = ""
    
    private enum FocusedField {
        case name
    }
    
    @FocusState private var focusedField: FocusedField?
    
    private var accentColor: Color = .orange
    private var grayBackground: Color = Color.gray.opacity(0.2)
    
    var body: some View {
            VStack {
                TextField(String(localized: "Name", comment:"Label of Name text field on Create new account screen"), text: $name)
                    .padding()
                    .background(grayBackground)
                    .cornerRadius(5.0)
                    .padding(.bottom, 20)
                    .focused($focusedField, equals: .name)
                TextField(String(localized:"Something about yourself (bio)", comment:"Label of bio/about text field on Create new account screen"), text: $about)
                    .lineLimit(5)
                    .padding()
                    .background(grayBackground)
                    .cornerRadius(5.0)
                    .padding(.bottom, 20)
                    
                Button {
                    createAccount()
                    if (!ns.onBoardingIsShown) {
                        dismiss()
                    }
                    NRState.shared.onBoardingIsShown = false
                    NRState.shared.loadAccountsState()
                } label: {
                    Text("Create")
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NRButtonStyle(theme: themes.theme, style: .borderedProminent))
                
                if (ns.accounts.first(where: { $0.publicKey == GUEST_ACCOUNT_PUBKEY}) == nil)  {
                    NavigationLink {
                        TryGuestAccountSheet()
                    } label: {
                        Text("Skip and try as guest first", comment: "Button to skip creating account and login as guest")
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
            .navigationTitle(String(localized:"Create new account", comment: "Navigation title of create new account screen"))
            .navigationBarTitleDisplayMode(.inline)
    }
    
    func createAccount() {
        let newAccount = AccountManager.shared.generateAccount(name: name, about: about, context: viewContext)
        do {
            
            guard let newKind0EventSigned = try AccountManager.createMetadataEvent(account: newAccount) else { throw "could not create newKind0EventSigned " }
            
            bg().perform {
                _ = Event.saveEvent(event: newKind0EventSigned)
                Contact.saveOrUpdateContact(event: newKind0EventSigned)
                
                DataProvider.shared().bgSave()
            }
            
            ns.changeAccount(newAccount)
            ns.onBoardingIsShown = false
        }
        catch {
            L.og.error("🔴🔴 could not ns.setAccount \(error)")
        }
    }
}

struct NewAccountSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewContainer {
            NewAccountSheet()
        }
    }
}
