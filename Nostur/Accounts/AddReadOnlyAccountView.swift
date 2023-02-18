////
////  NewReadOnlyAccountView.swift
////  Nostur
////
////  Created by Fabian Lachman on 10/01/2023.
////
//
//import SwiftUI
//
//struct AddReadOnlyAccountView: View {
//    @Environment(\.dismiss) private var dismiss
//    @State var npub = ""
//    @State var invalidKey = false
//    
//    var accentColor: Color = Color.blue
//    var grayBackground: Color = Color.gray.opacity(0.2)
//    
//    var onCreate: (_ pubkey:String) -> ()
//    
//    var body: some View {
//        
//        VStack{
//            Text("Add read only account")
//                .font(.title)
//                .foregroundColor(.accentColor)
//                .fontWeight(.semibold)
//                .padding(.bottom, 20)
//            TextField("Public key (npub)", text: $npub)
//                .padding()
//                .background(grayBackground)
//                .cornerRadius(5.0)
//                .padding(.bottom, 20)
//            Button {
//                guard let nip19 = try? NIP19(displayString: npub) else {
//                    invalidKey = true
//                    npub = ""
//                    return
//                }
//                onCreate(nip19.hexString)
//                dismiss()
//            } label: {
//                Text("Add")
//                    .font(.headline)
//                    .foregroundColor(.white)
//                    .padding()
//                    .frame(width: 220, height: 60)
//                    .background(accentColor)
//                    .cornerRadius(15.0)
//            }
//            Spacer()
//            Text("info...").foregroundColor(.gray)
//            
//        }.padding()
//            .alert("Invalid key", isPresented: $invalidKey) {
//                        Button("OK", role: .cancel) { }
//                    }
//    }
//}
//
//struct NewReadOnlyAccountView_Previews: PreviewProvider {
//    static var previews: some View {
//        AddReadOnlyAccountView { pubkey in
//            
//        }
//    }
//}
