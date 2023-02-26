//
//  AddExistingAccountSheet.swift
//  Nostur
//
//  Created by Fabian Lachman on 16/02/2023.
//

import SwiftUI

struct AddExistingAccountSheet: View {
    @EnvironmentObject var ns:NosturState
    @EnvironmentObject var nav:NavigationModel
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sp:SocketPool
    @State var key = ""
    @State var invalidKey = false
    
    var offerTryOut = false
    var accentColor: Color = Color.blue
    var grayBackground: Color = Color.gray.opacity(0.2)
    
    var body: some View {
        ZStack {
            VStack{
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
                Text("Add existing account")
                    .font(.title)
                
                TextField("Public or private key (npub or nsec)", text: $key)
                    .padding()
                    .background(grayBackground)
                    .cornerRadius(5.0)
                    .padding(.bottom, 20)
                
                Button {
                    guard let nip19 = try? NIP19(displayString: key) else {
                        invalidKey = true
                        key = ""
                        return
                    }
                    if (key.prefix(5) == "npub1") {
                        addExistingReadOnlyAccount(pubkey: nip19.hexString)
                        dismiss()
                    }
                    if (key.prefix(5) == "nsec1") {
                        addExistingAccount(privkey: nip19.hexString)
                        dismiss()
                    }
                    
                } label: {
                    Text("Add")
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 300)
                .buttonStyle(.borderedProminent)
                
                if (offerTryOut) {
                    Button {
                        nav.navigateTo(ViewPath.TryGuestAccount)
                        //                dismiss()
                    } label: {
                        Text("Skip and try as guest first")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 20)
                }
            }
            VStack {
                Spacer()
                Text("Note: You can also add someone elses public key to try out Nostur from their perspective.").foregroundColor(.gray)
            }
        }
        .controlSize(.large)
        .buttonStyle(.bordered)
        
        .padding()
        .alert("Invalid key", isPresented: $invalidKey) {
            Button("OK", role: .cancel) { }
        }
    }
    
    func addExistingAccount(privkey:String) {
        ns.pendingFirstContactsFetch = true
        let account = Account(context: viewContext)
        account.id = UUID()
        account.createdAt = Date()
        // TODO: Check if valid pubkey before save.
        
        guard let keys = try? NKeys(privateKeyHex: privkey) else {
            invalidKey = true
            key = ""
            return
        }
        
        account.publicKey = keys.publicKeyHex()
        account.privateKey = keys.privateKeyHex()
        
        // 1. Prefill from cached event
        Account.preFillReadOnlyAccountInfo(account: account, context: viewContext, forceOverwrite: true)
        Account.preFillReadOnlyAccountFollowing(account: account, context: viewContext)
        
        do {
            try viewContext.save()
            _ = ns.loadActiveAccount(account: account)
            
            // 2. But also check if there are newer events
            let message = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadataAndContactList(pubkey: account.publicKey!))
            sp.sendMessage(message)
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
    
    func addExistingReadOnlyAccount(pubkey:String) {
        ns.pendingFirstContactsFetch = true
        let account = Account(context: viewContext)
        account.id = UUID()
        account.createdAt = Date()
        // TODO: Check if valid pubkey before save.
        // Convert npub to hex... etc
        account.publicKey = pubkey
        
        // Remove existing CL events, so can proper parse again from Importers. Else get filtered by duplicate filter
        if let clEvents = Event.contactListEvents(byAuthorPubkey: account.publicKey!, context: viewContext) {
            for clEvent in clEvents {
                viewContext.delete(clEvent)
            }
        }
        
        // 1. Prefill from cached event
        Account.preFillReadOnlyAccountInfo(account: account, context: viewContext, forceOverwrite: true)
        Account.preFillReadOnlyAccountFollowing(account: account, context: viewContext)
        
        
        try! viewContext.save()
        _ = ns.loadActiveAccount(account: account)
        // 2. But also check if there are newer events
        let message = ClientMessage(type: .REQ, message: RequestMessage.getUserMetadataAndContactList(pubkey: pubkey))
        sp.sendMessage(message)
    }
}

struct AddExistingAccountSheet_Previews: PreviewProvider {
    static var previews: some View {
        AddExistingAccountSheet()
            .withPreviewEnvironment()
    }
}
