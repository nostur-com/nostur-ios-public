//
//  NewReadOnlyAccountView.swift
//  Nostur
//
//  Created by Fabian Lachman on 10/01/2023.
//

import SwiftUI

struct AddReadOnlyAccountView: View {
    @AppStorage("activeAccountPublicKey") var activeAccountPublicKey: String = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State var publicKeyHex = ""
    
    var accentColor: Color = Color.blue
    var grayBackground: Color = Color.gray.opacity(0.2)
    

    fileprivate func addReadOnlyAccount() {
        
        let identity = Identity(context: viewContext)
        identity.id = UUID()
        identity.createdAt = Date()
        identity.publicKey = publicKeyHex
        
        do {
            try viewContext.save()
            activeAccountPublicKey = publicKeyHex
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
            Text("Add read only account")
                .font(.title)
                .foregroundColor(.accentColor)
                .fontWeight(.semibold)
                .padding(.bottom, 20)
            TextField("Public key (hex)", text: $publicKeyHex)
                .padding()
                .background(grayBackground)
                .cornerRadius(5.0)
                .padding(.bottom, 20)
            Button {
                addReadOnlyAccount()
            } label: {
                Text("Add")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(width: 220, height: 60)
                    .background(accentColor)
                    .cornerRadius(15.0)
            }
            Spacer()
            Text("info...").foregroundColor(.gray)
            
        }.padding()
    }
}

struct NewReadOnlyAccountView_Previews: PreviewProvider {
    static var previews: some View {
        AddReadOnlyAccountView()
    }
}
