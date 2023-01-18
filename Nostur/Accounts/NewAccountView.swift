//
//  NewIdentityView.swift
//  Nostur
//
//  Created by Fabian Lachman on 07/01/2023.
//

import SwiftUI
import secp256k1
import Foundation

struct NewAccountView: View {
    
    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var addReadOnlyAccountPresented: Bool
    
    @State var name = ""
    @State var about = ""
    
    var accentColor: Color = Color.blue
    var grayBackground: Color = Color.gray.opacity(0.2)
    

    fileprivate func createAccount() {

        let newKeys = NKeys.newKeys()
        
//        print("Private key: \(privateKeyHex)") for testing. dont print this ever
        print("Public key: \(newKeys.publicKeyHex())")

        let identity = Identity(context: viewContext)
        identity.id = UUID()
        identity.createdAt = Date()
        identity.name = name
        identity.about = about
        identity.privateKey = newKeys.privateKeyHex()
        identity.publicKey = newKeys.publicKeyHex()
        
        do {
            try viewContext.save()
            activeAccountPublicKey = newKeys.publicKeyHex()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        dismiss()
    }
    
    var body: some View {
        
        VStack{
            Text("Create account")
                .font(.largeTitle)
                .foregroundColor(.accentColor)
                .fontWeight(.semibold)
                .padding(.bottom, 20)
            TextField("Name", text: $name)
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
            } label: {
                Text("Create")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(width: 220, height: 60)
                    .background(accentColor)
                    .cornerRadius(15.0)
            }
            Spacer()
            Button {
                addReadOnlyAccountPresented = true
                dismiss()
            } label: {
                Text("Or add read-only account")
            }
//            Text("creates local account..").foregroundColor(.gray)
            
        }.padding()
    }
}



struct NewIdentityView_Previews: PreviewProvider {
    static var previews: some View {
        NewAccountView(addReadOnlyAccountPresented: .constant(false)).environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
}
