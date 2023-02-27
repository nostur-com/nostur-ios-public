//
//  NewAccountSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/02/2023.
//

import SwiftUI

//
//  NewAccountView.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/01/2023.
//

import SwiftUI
import secp256k1
import Foundation

struct NewAccountSheet: View {
    
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var nav:NavigationModel
    @EnvironmentObject var up:Unpublisher
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State var display_name = ""
    @State var name = ""
    @State var about = ""
    
    enum FocusedField {
        case display_name
    }
    
    @FocusState private var focusedField: FocusedField?
    
    var accentColor: Color = .orange
    var grayBackground: Color = Color.gray.opacity(0.2)
    
    var body: some View {
        
        VStack {
            if UIDevice.current.userInterfaceIdiom == .pad {
                HStack {
                    Spacer()
                    Image(systemName: "xmark.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .padding(30)
                        .onTapGesture {
                            dismiss()
                        }
                }
            }
            
            Text("Create new account")
                .font(.largeTitle)
                
            TextField("Full Name", text: $display_name)
                .padding()
                .background(grayBackground)
                .cornerRadius(5.0)
                .padding(.bottom, 20)
                .focused($focusedField, equals: .display_name)
            TextField("Username/Handle", text: $name)
                .padding()
                .background(grayBackground)
                .cornerRadius(5.0)
                .padding(.bottom, 20)
            TextField("Something about yourself (bio)", text: $about)
                .lineLimit(5)
                .padding()
                .background(grayBackground)
                .cornerRadius(5.0)
                .padding(.bottom, 20)
                
            Button {
                createAccount()
//                dismiss()
            } label: {
                Text("Create")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            if (ns.accounts.first(where: { $0.publicKey == NosturState.GUEST_ACCOUNT_PUBKEY}) == nil) {
                Button {
                    nav.navigateTo(ViewPath.TryGuestAccount)
                } label: {
                    Text("Skip and try as guest first")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .padding(.top, 20)
            }
            
        }
        .frame(maxWidth: 300)
        .controlSize(.large)
        .buttonStyle(.bordered)
        .onAppear { focusedField = .display_name }
    }
    
    func createAccount() {
        let newAccount = AccountManager.shared.generateAccount(display_name: display_name, name: name, about: about, context: viewContext)

        do {
            
            guard let newKind0EventSigned = try AccountManager.createMetadataEvent(account: newAccount) else { throw "could not create newKind0EventSigned " }
            
            _ = Event.saveEvent(event: newKind0EventSigned, context: viewContext)
            Contact.saveOrUpdateContact(event: newKind0EventSigned, context: viewContext)
            
            try viewContext.save()
            
            // broadcast to relays
//            up.publishNow(newKind0EventSigned) // TODO: Publish later? its probably empty now, will fill with follow
            ns.setAccount(account: newAccount)
            ns.onBoardingIsShown = false
        }
        catch {
            print("🔴🔴 could not ns.setAccount")
            print(error)
        }
    }
}

struct NewAccountSheet_Previews: PreviewProvider {
    static var previews: some View {
        NewAccountSheet()
            .withPreviewEnvironment()
    }
}
