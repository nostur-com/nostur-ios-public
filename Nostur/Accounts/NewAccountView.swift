//
//  NewAccountView.swift
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
    
    var accentColor: Color = .orange
    var grayBackground: Color = Color.gray.opacity(0.2)
    
    var onCreate: (_ name:String, _ about:String) -> ()
    
    var body: some View {
        
        VStack{
            Text("Create account")
                .font(.largeTitle)
                .foregroundColor(Color("OrangeColor"))
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
                onCreate(name, about)
                dismiss()
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



struct NewAccountView_Previews: PreviewProvider {
    static var previews: some View {
        NewAccountView(addReadOnlyAccountPresented: .constant(false), onCreate: { name, about in
            
        })
            .environment(\.managedObjectContext, EventsProvider.shared.container.viewContext)
    }
}
